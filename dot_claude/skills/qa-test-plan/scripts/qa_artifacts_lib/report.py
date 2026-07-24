from __future__ import annotations

import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import Final

from jinja2 import Environment, FileSystemLoader, select_autoescape
from PIL import Image, ImageDraw, ImageFont
from qa_artifacts_lib.models import (
    BoundRun,
    Persona,
    QAPlan,
    QAScenario,
    QAStep,
    Requirement,
    ResultStatus,
    ScenarioResult,
    StepResult,
)

STATUS_COLORS: Final[dict[ResultStatus, str]] = {
    ResultStatus.PASS: "#0B7F3F",
    ResultStatus.FAIL: "#D92D20",
    ResultStatus.BLOCKED: "#F79009",
    ResultStatus.SKIPPED: "#667085",
}


@dataclass(frozen=True, slots=True)
class StepView:
    plan: QAStep
    result: StepResult
    screenshot_raw: str | None
    screenshot_annotated: str | None


@dataclass(frozen=True, slots=True)
class ScenarioView:
    plan: QAScenario
    result: ScenarioResult
    persona: Persona
    captions_path: str | None
    steps: list[StepView]


@dataclass(frozen=True, slots=True)
class RequirementView:
    requirement: Requirement
    scenario_ids: list[str]
    statuses: list[ResultStatus]


@dataclass(frozen=True, slots=True)
class ReportView:
    run: BoundRun
    overall_status: ResultStatus
    counts: dict[ResultStatus, int]
    requirements: list[RequirementView]
    scenarios: list[ScenarioView]


@dataclass(frozen=True, slots=True)
class ScreenshotAnnotation:
    source: Path
    output: Path
    plan: QAStep
    result: StepResult


@dataclass(frozen=True, slots=True)
class ScenarioCaption:
    bundle_dir: Path
    video_path: str
    plan: QAScenario
    result: ScenarioResult


def render_plan(plan: QAPlan, templates_dir: Path, output: Path) -> None:
    environment = _template_environment(templates_dir)
    content = environment.get_template("qa-plan.md").render(plan=plan)
    _ = output.write_text(content.rstrip() + "\n", encoding="utf-8")


def render_report(run: BoundRun, templates_dir: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    scenarios = _build_scenario_views(run, output.parent)
    view = ReportView(
        run=run,
        overall_status=_overall_status(run),
        counts=_status_counts(run),
        requirements=_requirement_views(run),
        scenarios=scenarios,
    )
    environment = _template_environment(templates_dir)
    content = environment.get_template("report.html").render(report=view)
    _ = output.write_text(content, encoding="utf-8")


def _build_scenario_views(run: BoundRun, bundle_dir: Path) -> list[ScenarioView]:
    scenarios_by_id = {scenario.id: scenario for scenario in run.plan.scenarios}
    personas_by_id = {persona.id: persona for persona in run.plan.personas}
    views: list[ScenarioView] = []
    for result in run.results.scenarios:
        scenario = scenarios_by_id[result.scenario_id]
        video_path = result.video_path
        captions_path = (
            _write_vtt(
                ScenarioCaption(
                    bundle_dir=bundle_dir,
                    video_path=video_path,
                    plan=scenario,
                    result=result,
                )
            )
            if video_path
            else None
        )
        steps = [
            _build_step_view(bundle_dir, plan_step, result_step)
            for plan_step, result_step in zip(scenario.steps, result.steps, strict=True)
        ]
        views.append(
            ScenarioView(
                plan=scenario,
                result=result,
                persona=personas_by_id[scenario.persona_id],
                captions_path=captions_path,
                steps=steps,
            )
        )
    return views


def _build_step_view(bundle_dir: Path, plan: QAStep, result: StepResult) -> StepView:
    raw_path = result.screenshot_raw
    if raw_path is None:
        return StepView(
            plan=plan, result=result, screenshot_raw=None, screenshot_annotated=None
        )
    raw_file = bundle_dir / raw_path
    annotated_file = raw_file.with_name(f"{raw_file.stem}-annotated.png")
    _annotate_screenshot(
        ScreenshotAnnotation(
            source=raw_file, output=annotated_file, plan=plan, result=result
        )
    )
    return StepView(
        plan=plan,
        result=result,
        screenshot_raw=raw_path,
        screenshot_annotated=annotated_file.relative_to(bundle_dir).as_posix(),
    )


def _annotate_screenshot(annotation: ScreenshotAnnotation) -> None:
    plan = annotation.plan
    result = annotation.result
    with Image.open(annotation.source) as raw_image:
        screenshot = raw_image.convert("RGB")
    draw = ImageDraw.Draw(screenshot)
    if result.highlight_box is not None:
        box = result.highlight_box
        draw.rectangle(
            (box.x, box.y, box.x + box.width, box.y + box.height),
            outline=_status_color(result.status),
            width=5,
        )
    caption = (
        f"{plan.id} [{result.status.value.upper()}]\n"
        f"Action: {plan.action}\nExpected: {plan.expected}\nObserved: {result.observed}"
    )
    lines = [
        line
        for paragraph in caption.splitlines()
        for line in textwrap.wrap(paragraph, width=105)
    ]
    font = ImageFont.load_default(size=16)
    canvas_width = max(screenshot.width, 960)
    line_height = 22
    caption_height = 28 + (len(lines) * line_height)
    canvas = Image.new(
        "RGB", (canvas_width, screenshot.height + caption_height), "white"
    )
    canvas.paste(screenshot, ((canvas_width - screenshot.width) // 2, 0))
    canvas_draw = ImageDraw.Draw(canvas)
    canvas_draw.rectangle(
        (0, screenshot.height, canvas_width, screenshot.height + caption_height),
        fill="#101828",
    )
    canvas_draw.rectangle(
        (0, screenshot.height, 10, screenshot.height + caption_height),
        fill=_status_color(result.status),
    )
    y = screenshot.height + 14
    for line in lines:
        canvas_draw.text((24, y), line, fill="white", font=font)
        y += line_height
    annotation.output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(annotation.output, format="PNG")


def _write_vtt(caption: ScenarioCaption) -> str:
    video_file = caption.bundle_dir / caption.video_path
    captions_file = video_file.with_name(f"{caption.plan.id}.vtt")
    cues = ["WEBVTT", ""]
    for plan_step, result_step in zip(
        caption.plan.steps, caption.result.steps, strict=True
    ):
        cues.extend(
            (
                plan_step.id,
                f"{_vtt_time(result_step.video_start_seconds)} --> {_vtt_time(result_step.video_end_seconds)}",
                (
                    f"{plan_step.action} | Expected: {plan_step.expected} | "
                    f"Observed: {result_step.observed} | {result_step.status.value.upper()}"
                ),
                "",
            )
        )
    _ = captions_file.write_text("\n".join(cues), encoding="utf-8")
    return captions_file.relative_to(caption.bundle_dir).as_posix()


def _vtt_time(seconds: float) -> str:
    milliseconds = round(seconds * 1000)
    hours, remainder = divmod(milliseconds, 3_600_000)
    minutes, remainder = divmod(remainder, 60_000)
    secs, millis = divmod(remainder, 1000)
    return f"{hours:02}:{minutes:02}:{secs:02}.{millis:03}"


def _overall_status(run: BoundRun) -> ResultStatus:
    statuses = [scenario.status for scenario in run.results.scenarios]
    if ResultStatus.FAIL in statuses:
        return ResultStatus.FAIL
    if ResultStatus.BLOCKED in statuses:
        return ResultStatus.BLOCKED
    if all(status is ResultStatus.SKIPPED for status in statuses):
        return ResultStatus.SKIPPED
    return ResultStatus.PASS


def _status_counts(run: BoundRun) -> dict[ResultStatus, int]:
    return {
        status: sum(result.status is status for result in run.results.scenarios)
        for status in ResultStatus
    }


def _requirement_views(run: BoundRun) -> list[RequirementView]:
    status_by_scenario = {
        result.scenario_id: result.status for result in run.results.scenarios
    }
    views: list[RequirementView] = []
    for requirement in run.plan.requirements:
        scenario_ids = [
            scenario.id
            for scenario in run.plan.scenarios
            if requirement.id in scenario.requirement_ids
        ]
        views.append(
            RequirementView(
                requirement=requirement,
                scenario_ids=scenario_ids,
                statuses=[
                    status_by_scenario[scenario_id] for scenario_id in scenario_ids
                ],
            )
        )
    return views


def _status_color(status: ResultStatus) -> str:
    return STATUS_COLORS[status]


def _template_environment(templates_dir: Path) -> Environment:
    return Environment(
        loader=FileSystemLoader(templates_dir),
        autoescape=select_autoescape(enabled_extensions=("html",)),
        trim_blocks=True,
        lstrip_blocks=True,
    )
