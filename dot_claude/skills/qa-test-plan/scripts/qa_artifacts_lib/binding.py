from __future__ import annotations

from pathlib import Path

import yaml
from pydantic_core import PydanticCustomError
from qa_artifacts_lib.models import (
    BoundRun,
    QAPlan,
    QAResults,
    ResultStatus,
    ScreenshotPolicy,
)


def load_plan(path: Path) -> QAPlan:
    with path.open(encoding="utf-8") as stream:
        return QAPlan.model_validate(yaml.safe_load(stream))


def load_results(path: Path) -> QAResults:
    return QAResults.model_validate_json(path.read_text(encoding="utf-8"))


def bind_run(plan: QAPlan, results: QAResults) -> BoundRun:
    if results.plan_id != plan.plan_id:
        raise PydanticCustomError(
            "plan_id_mismatch",
            "results plan_id {actual} does not match {expected}",
            {"actual": results.plan_id, "expected": plan.plan_id},
        )
    planned = {
        scenario.id: [step.id for step in scenario.steps] for scenario in plan.scenarios
    }
    executed = {
        scenario.scenario_id: [step.step_id for step in scenario.steps]
        for scenario in results.scenarios
    }
    if planned != executed:
        raise PydanticCustomError(
            "execution_coverage",
            "results must contain every planned scenario and step exactly once",
        )
    results_by_scenario = {
        scenario.scenario_id: scenario for scenario in results.scenarios
    }
    for scenario in plan.scenarios:
        result = results_by_scenario[scenario.id]
        if (
            any(step.evidence.video for step in scenario.steps)
            and result.status in {ResultStatus.PASS, ResultStatus.FAIL}
            and result.video_path is None
        ):
            raise PydanticCustomError(
                "missing_video",
                "scenario {scenario_id} requires a video",
                {"scenario_id": scenario.id},
            )
        for plan_step, result_step in zip(scenario.steps, result.steps, strict=True):
            screenshot_required = (
                plan_step.evidence.screenshot is ScreenshotPolicy.AFTER
                or (
                    plan_step.evidence.screenshot is ScreenshotPolicy.ON_FAILURE
                    and result_step.status is ResultStatus.FAIL
                )
            )
            if screenshot_required and result_step.screenshot_raw is None:
                raise PydanticCustomError(
                    "missing_screenshot",
                    "step {step_id} requires a screenshot",
                    {"step_id": plan_step.id},
                )
    return BoundRun(plan=plan, results=results)
