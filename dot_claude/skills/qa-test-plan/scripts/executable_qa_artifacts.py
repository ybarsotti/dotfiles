#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "jinja2>=3.1,<4",
#     "pillow>=11,<13",
#     "pydantic>=2.11,<3",
#     "pyyaml>=6,<7",
#     "typer>=0.16,<1",
# ]
# ///

# ─── How to run ───
# 1. Install uv (if not installed):
#      curl -LsSf https://astral.sh/uv/install.sh | sh
# 2. Run directly (no venv, no pip install needed):
#      uv run qa_artifacts.py --help
# 3. Or make executable and run:
#      chmod +x qa_artifacts.py && ./qa_artifacts.py --help
# ──────────────────

from __future__ import annotations

import json
from pathlib import Path
from typing import Annotated

import typer
from qa_artifacts_lib.binding import bind_run, load_plan, load_results
from qa_artifacts_lib.models import QAPlan, QAResults
from qa_artifacts_lib.report import render_plan as render_plan_document
from qa_artifacts_lib.report import render_report as render_html_report

app = typer.Typer(
    add_completion=False,
    no_args_is_help=True,
    help="Validate QA contracts and render manual plans, captions, annotated screenshots, and HTML.",
)
SCRIPT_DIR = Path(__file__).resolve().parent
TEMPLATES_DIR = SCRIPT_DIR.parent / "templates"


@app.command("validate-plan")
def validate_plan(
    plan_path: Annotated[Path, typer.Argument(exists=True, readable=True)],
) -> None:
    """Parse a QA plan and reject invalid or dangling references."""
    plan = load_plan(plan_path)
    typer.echo(f"valid QA plan: {plan.plan_id} ({len(plan.scenarios)} scenarios)")


@app.command("render-plan")
def render_plan(
    plan_path: Annotated[Path, typer.Argument(exists=True, readable=True)],
    output: Annotated[Path, typer.Argument()],
) -> None:
    """Render human-readable Markdown from the structured QA plan."""
    plan = load_plan(plan_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    render_plan_document(plan, TEMPLATES_DIR, output)
    typer.echo(output)


@app.command("validate-results")
def validate_results(
    plan_path: Annotated[Path, typer.Argument(exists=True, readable=True)],
    results_path: Annotated[Path, typer.Argument(exists=True, readable=True)],
) -> None:
    """Parse results and prove complete scenario/step coverage against the plan."""
    run = bind_run(load_plan(plan_path), load_results(results_path))
    typer.echo(f"valid QA results: {run.results.run_id}")


@app.command("render-report")
def render_report(
    plan_path: Annotated[Path, typer.Argument(exists=True, readable=True)],
    results_path: Annotated[Path, typer.Argument(exists=True, readable=True)],
    output: Annotated[Path, typer.Argument()],
) -> None:
    """Render HTML, WebVTT captions, and annotated screenshots from a bound run."""
    run = bind_run(load_plan(plan_path), load_results(results_path))
    render_html_report(run, TEMPLATES_DIR, output)
    typer.echo(output)


@app.command("write-schemas")
def write_schemas(output_dir: Annotated[Path, typer.Argument()]) -> None:
    """Write versioned JSON Schemas for QA plan and results contracts."""
    output_dir.mkdir(parents=True, exist_ok=True)
    plan_schema = json.dumps(QAPlan.model_json_schema(), indent=2, sort_keys=True)
    results_schema = json.dumps(QAResults.model_json_schema(), indent=2, sort_keys=True)
    _ = (output_dir / "qa-plan.schema.json").write_text(
        plan_schema + "\n", encoding="utf-8"
    )
    _ = (output_dir / "qa-results.schema.json").write_text(
        results_schema + "\n", encoding="utf-8"
    )
    typer.echo(output_dir)


if __name__ == "__main__":
    app()
