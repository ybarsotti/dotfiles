from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from pathlib import PurePosixPath
from typing import Annotated, ClassVar, Literal, Self

from pydantic import (
    AfterValidator,
    BaseModel,
    ConfigDict,
    Field,
    HttpUrl,
    model_validator,
)
from pydantic_core import PydanticCustomError

SchemaVersion = Literal["1.0"]
Identifier = Annotated[
    str, Field(min_length=1, pattern=r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
]
CommitSha = Annotated[str, Field(pattern=r"^[0-9a-f]{40}$")]
NonEmptyText = Annotated[str, Field(min_length=1)]


def _parse_relative_path(raw: str) -> str:
    path = PurePosixPath(raw)
    if path.is_absolute() or ".." in path.parts:
        raise PydanticCustomError(
            "relative_artifact_path",
            "artifact path must stay inside the QA bundle: {path}",
            {"path": raw},
        )
    return path.as_posix()


RelativeArtifactPath = Annotated[str, AfterValidator(_parse_relative_path)]


class FrozenModel(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")


class ScreenshotPolicy(StrEnum):
    NONE = "none"
    AFTER = "after"
    ON_FAILURE = "on-failure"


class CapturePolicy(StrEnum):
    NONE = "none"
    ERRORS = "errors"
    ALL = "all"


class ResultStatus(StrEnum):
    PASS = "pass"
    FAIL = "fail"
    BLOCKED = "blocked"
    SKIPPED = "skipped"


class Requirement(FrozenModel):
    id: Identifier
    text: NonEmptyText


class Persona(FrozenModel):
    id: Identifier
    name: NonEmptyText
    description: NonEmptyText


class EvidencePolicy(FrozenModel):
    screenshot: ScreenshotPolicy = ScreenshotPolicy.AFTER
    video: bool = True
    console: CapturePolicy = CapturePolicy.ERRORS
    network: CapturePolicy = CapturePolicy.ERRORS


class QAStep(FrozenModel):
    id: Identifier
    screen: NonEmptyText
    action: NonEmptyText
    input: str | None = None
    expected: NonEmptyText
    evidence: EvidencePolicy


class QAScenario(FrozenModel):
    id: Identifier
    name: NonEmptyText
    requirement_ids: Annotated[list[Identifier], Field(min_length=1)]
    persona_id: Identifier
    preconditions: Annotated[list[NonEmptyText], Field(min_length=1)]
    test_data: list[NonEmptyText] = Field(default_factory=list)
    steps: Annotated[list[QAStep], Field(min_length=1)]
    edge_cases: Annotated[list[NonEmptyText], Field(min_length=1)]
    acceptance_rules: Annotated[list[NonEmptyText], Field(min_length=1)]


class QAPlan(FrozenModel):
    schema_version: SchemaVersion
    plan_id: Identifier
    feature: NonEmptyText
    ticket: str | None
    source_plan: NonEmptyText
    requirements: Annotated[list[Requirement], Field(min_length=1)]
    personas: Annotated[list[Persona], Field(min_length=1)]
    scenarios: Annotated[list[QAScenario], Field(min_length=1)]

    @model_validator(mode="after")
    def references_exist(self) -> Self:
        requirement_ids = [requirement.id for requirement in self.requirements]
        persona_ids = [persona.id for persona in self.personas]
        scenario_ids = [scenario.id for scenario in self.scenarios]
        _require_unique("requirement", requirement_ids)
        _require_unique("persona", persona_ids)
        _require_unique("scenario", scenario_ids)
        for scenario in self.scenarios:
            _require_known("persona", scenario.persona_id, persona_ids)
            _require_unique("step", [step.id for step in scenario.steps])
            for requirement_id in scenario.requirement_ids:
                _require_known("requirement", requirement_id, requirement_ids)
        return self


class QAEnvironment(FrozenModel):
    commit_sha: CommitSha
    base_url: HttpUrl
    browser: NonEmptyText
    viewport: Annotated[str, Field(pattern=r"^\d+x\d+$")]
    feature_flags: list[str] = Field(default_factory=list)


class HighlightBox(FrozenModel):
    x: Annotated[int, Field(ge=0)]
    y: Annotated[int, Field(ge=0)]
    width: Annotated[int, Field(gt=0)]
    height: Annotated[int, Field(gt=0)]


class StepResult(FrozenModel):
    step_id: Identifier
    status: ResultStatus
    observed: NonEmptyText
    started_at: datetime
    finished_at: datetime
    video_start_seconds: Annotated[float, Field(ge=0)]
    video_end_seconds: Annotated[float, Field(gt=0)]
    screenshot_raw: RelativeArtifactPath | None = None
    highlight_box: HighlightBox | None = None
    console_errors: list[str] = Field(default_factory=list)
    network_errors: list[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def interval_is_ordered(self) -> Self:
        if (
            self.finished_at < self.started_at
            or self.video_end_seconds <= self.video_start_seconds
        ):
            raise PydanticCustomError(
                "ordered_interval",
                "step {step_id} has an invalid time interval",
                {"step_id": self.step_id},
            )
        return self


class ScenarioResult(FrozenModel):
    scenario_id: Identifier
    status: ResultStatus
    started_at: datetime
    finished_at: datetime
    video_path: RelativeArtifactPath | None
    steps: Annotated[list[StepResult], Field(min_length=1)]

    @model_validator(mode="after")
    def scenario_is_consistent(self) -> Self:
        _require_unique("result step", [step.step_id for step in self.steps])
        if self.finished_at < self.started_at:
            raise PydanticCustomError(
                "ordered_interval",
                "scenario {scenario_id} has an invalid time interval",
                {"scenario_id": self.scenario_id},
            )
        if (
            any(step.status is ResultStatus.FAIL for step in self.steps)
            and self.status is not ResultStatus.FAIL
        ):
            raise PydanticCustomError(
                "scenario_status",
                "scenario {scenario_id} must fail when a step fails",
                {"scenario_id": self.scenario_id},
            )
        return self


class QAResults(FrozenModel):
    schema_version: SchemaVersion
    run_id: Identifier
    plan_id: Identifier
    attempt: Annotated[int, Field(ge=1)]
    environment: QAEnvironment
    started_at: datetime
    finished_at: datetime
    scenarios: Annotated[list[ScenarioResult], Field(min_length=1)]

    @model_validator(mode="after")
    def run_is_consistent(self) -> Self:
        _require_unique(
            "result scenario", [scenario.scenario_id for scenario in self.scenarios]
        )
        if self.finished_at < self.started_at:
            raise PydanticCustomError(
                "ordered_interval", "QA run has an invalid time interval"
            )
        return self


@dataclass(frozen=True, slots=True)
class BoundRun:
    plan: QAPlan
    results: QAResults


def _require_unique(kind: str, identifiers: list[str]) -> None:
    if len(identifiers) != len(set(identifiers)):
        raise PydanticCustomError(
            "duplicate_identifier",
            "{kind} identifiers must be unique",
            {"kind": kind},
        )


def _require_known(kind: str, identifier: str, known: list[str]) -> None:
    if identifier not in known:
        raise PydanticCustomError(
            "unknown_reference",
            "unknown {kind} reference: {identifier}",
            {"kind": kind, "identifier": identifier},
        )
