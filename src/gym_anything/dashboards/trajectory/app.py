from __future__ import annotations

import argparse
import importlib
import json
import traceback
from io import BytesIO
from pathlib import Path
from typing import Any

from flask import Flask, current_app, jsonify, render_template, request, send_file

from .run_store import (
    compare_experiments,
    extract_gpt54_trajectory_steps,
    extract_owl_trajectory_steps,
    extract_trajectory_steps,
    format_tool_call,
    get_all_runs,
    get_delta_frame_as_png,
    get_run_summary,
    has_delta_compression,
    is_gpt54_run,
    is_owl_run,
    load_info,
    load_messages,
    load_owl_info,
    load_owl_parsed_responses,
)


def _resolved_runs(runs_root: Path, constraint: str | None) -> list[dict[str, Any]]:
    runs = get_all_runs(str(runs_root), constraint)
    resolved_runs: list[dict[str, Any]] = []
    for run in runs:
        resolved_run = dict(run)
        resolved_run["run_path"] = str(Path(run["run_path"]).resolve(strict=False))
        resolved_runs.append(resolved_run)
    return resolved_runs


def _known_run_map() -> dict[str, dict[str, Any]]:
    return current_app.config["TRAJECTORY_RUNS_BY_PATH"]


def _known_run_dirs() -> list[Path]:
    return current_app.config["TRAJECTORY_RUN_DIRS"]


def _get_known_run(run_path: str) -> tuple[dict[str, Any] | None, Path | None]:
    resolved = str(Path(run_path).resolve(strict=False))
    run = _known_run_map().get(resolved)
    if run is None:
        return None, None
    return run, Path(resolved)


def _path_within_known_run(path_str: str) -> Path | None:
    path = Path(path_str).resolve(strict=False)
    for run_dir in _known_run_dirs():
        if path.is_relative_to(run_dir):
            return path
    return None


def _load_task_description(run_dir: Path, messages: list[dict[str, Any]]) -> str:
    if messages and messages[0].get("role") == "user":
        content = messages[0].get("content", "")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            text_parts = []
            for item in content:
                if isinstance(item, dict) and item.get("type") == "text":
                    text_parts.append(item.get("text", ""))
                elif hasattr(item, "type") and item.type == "text":
                    text_parts.append(item.text if hasattr(item, "text") else "")
            return " ".join(part for part in text_parts if part)
    return f"Task: {run_dir.parent.name}"


def _load_owl_task_description(run_dir: Path) -> str:
    task_name = run_dir.parent.name
    task_json_path = Path("examples/gimp_env_all") / "tasks" / task_name / "task.json"
    if not task_json_path.exists():
        return f"Task: {task_name}"
    try:
        with task_json_path.open("r", encoding="utf-8") as handle:
            task_data = json.load(handle)
        return task_data.get("description", f"Task: {task_name}")
    except Exception:
        return f"Task: {task_name}"


def _load_run_details(run_dir: Path) -> dict[str, Any]:
    owl_run = is_owl_run(run_dir)
    gpt54_run = is_gpt54_run(run_dir)

    if owl_run:
        parsed_responses_json = run_dir / "parsed_responses.json"
        info_json = run_dir / "info.json"
        parsed_responses = (
            load_owl_parsed_responses(str(parsed_responses_json))
            if parsed_responses_json.exists()
            else []
        )
        info = load_owl_info(str(info_json)) if info_json.exists() else {}
        summary = get_run_summary(str(run_dir))
        steps = extract_owl_trajectory_steps(parsed_responses, run_dir)
        task_description = _load_owl_task_description(run_dir)
    elif gpt54_run:
        responses_meta_path = run_dir / "responses_metadata.json"
        action_history_path = run_dir / "action_history.json"
        info_json_path = run_dir / "info.json"
        responses_metadata = []
        action_history = []
        info = {}

        if responses_meta_path.exists():
            with responses_meta_path.open("r", encoding="utf-8") as handle:
                responses_metadata = json.load(handle)
        if action_history_path.exists():
            with action_history_path.open("r", encoding="utf-8") as handle:
                action_history = json.load(handle)
        if info_json_path.exists():
            with info_json_path.open("r", encoding="utf-8") as handle:
                info = json.load(handle)

        summary = get_run_summary(str(run_dir))
        steps = extract_gpt54_trajectory_steps(responses_metadata, action_history, run_dir)
        task_description = (
            responses_metadata[0].get("text_output", "")
            if responses_metadata
            else f"Task: {run_dir.parent.name}"
        )
    else:
        messages_pkl = run_dir / "messages.pkl"
        info_pkl = run_dir / "info.pkl"
        messages = load_messages(str(messages_pkl)) if messages_pkl.exists() else []
        info = load_info(str(info_pkl)) if info_pkl.exists() else {}
        summary = get_run_summary(str(run_dir))
        steps = extract_trajectory_steps(messages, run_dir)
        task_description = _load_task_description(run_dir, messages)

    skip_tool_format = owl_run or gpt54_run
    steps_data = []
    for step in steps:
        steps_data.append(
            {
                "step_num": step["step_num"],
                "observation_path": str(step["observation_path"]) if step["observation_path"] else None,
                "thinking": step["thinking"],
                "text_response": step["text_response"],
                "tool_calls": [
                    tool_call if skip_tool_format else format_tool_call(tool_call)
                    for tool_call in step["tool_calls"]
                ],
                "tool_outputs": [str(tool_output) for tool_output in step["tool_outputs"]],
            }
        )

    return {
        "run_path": str(run_dir),
        "summary": summary,
        "task_description": task_description,
        "steps": steps_data,
        "total_steps": len(steps_data),
        "info": info,
        "pdf_exists": (run_dir / "trajectory_report.pdf").exists(),
        "gif_exists": (run_dir / "trajectory.gif").exists(),
        "is_owl": owl_run,
    }


def _serve_precomputed_or_generate(run_dir: Path, filename: str, module_name: str, function_name: str, mimetype: str):
    artifact_path = run_dir / filename
    if artifact_path.exists():
        return send_file(str(artifact_path), mimetype=mimetype)

    try:
        module = importlib.import_module(module_name)
        generator = getattr(module, function_name)
    except Exception:
        return jsonify(
            {
                "error": (
                    f"{filename} not found and generator module '{module_name}' is not available "
                    "in this checkout."
                )
            }
        ), 404

    try:
        generator(str(run_dir))
    except Exception as exc:
        return jsonify({"error": f"Failed to generate {filename}: {exc}"}), 500

    if artifact_path.exists():
        return send_file(str(artifact_path), mimetype=mimetype)
    return jsonify({"error": f"{filename} was not created"}), 500


def _requested_path(path_from_route: str | None = None) -> str | None:
    if path_from_route:
        return path_from_route
    return request.args.get("path")


def create_app(runs_root: str | Path = "all_runs", constraint: str | None = None) -> Flask:
    app = Flask(__name__)

    resolved_root = Path(runs_root).resolve(strict=False)
    runs = _resolved_runs(resolved_root, constraint)
    app.config["TRAJECTORY_RUNS_ROOT"] = str(resolved_root)
    app.config["TRAJECTORY_CONSTRAINT"] = constraint
    app.config["TRAJECTORY_RUNS"] = runs
    app.config["TRAJECTORY_RUNS_BY_PATH"] = {run["run_path"]: run for run in runs}
    app.config["TRAJECTORY_RUN_DIRS"] = [Path(run["run_path"]) for run in runs]

    @app.get("/")
    def index():
        return render_template(
            "index.html",
            runs_root=str(resolved_root),
            run_count=len(runs),
            constraint=constraint,
        )

    @app.get("/api/runs")
    def api_runs():
        return jsonify(
            {
                "experiments": sorted({run["experiment"] for run in runs}),
                "runs": runs,
                "runs_root": str(resolved_root),
                "constraint": constraint,
            }
        )

    @app.get("/api/run")
    @app.get("/api/run/<path:run_path>")
    def api_run_details(run_path: str | None = None):
        requested_path = _requested_path(run_path)
        if not requested_path:
            return jsonify({"error": "Missing run path"}), 400
        run, run_dir = _get_known_run(requested_path)
        if run is None or run_dir is None:
            return jsonify({"error": "Run not found in the indexed runs root"}), 404
        try:
            return jsonify(_load_run_details(run_dir))
        except Exception as exc:
            traceback.print_exc()
            return jsonify({"error": str(exc)}), 500

    @app.get("/api/image")
    @app.get("/api/image/<path:image_path>")
    def api_image(image_path: str | None = None):
        requested_path = _requested_path(image_path)
        if not requested_path:
            return jsonify({"error": "Missing image path"}), 400
        img_path = _path_within_known_run(requested_path)
        if img_path is None:
            return jsonify({"error": "Image path is outside indexed runs"}), 404

        if img_path.exists() and img_path.suffix == ".png":
            return send_file(str(img_path), mimetype="image/png")

        if img_path.name.startswith("observation_") and img_path.suffix == ".png":
            run_dir = img_path.parent
            if has_delta_compression(run_dir):
                try:
                    step_num = int(img_path.stem.split("_")[1])
                    png_bytes = get_delta_frame_as_png(run_dir, step_num)
                    if png_bytes:
                        return send_file(BytesIO(png_bytes), mimetype="image/png")
                except (ValueError, IndexError):
                    pass

        return jsonify({"error": "Image not found"}), 404

    @app.get("/api/pdf")
    @app.get("/api/pdf/<path:run_path>")
    def api_pdf(run_path: str | None = None):
        requested_path = _requested_path(run_path)
        if not requested_path:
            return jsonify({"error": "Missing run path"}), 400
        run, run_dir = _get_known_run(requested_path)
        if run is None or run_dir is None:
            return jsonify({"error": "Run not found in the indexed runs root"}), 404
        return _serve_precomputed_or_generate(
            run_dir,
            "trajectory_report.pdf",
            "generate_pdf_report",
            "create_pdf_report",
            "application/pdf",
        )

    @app.get("/api/gif")
    @app.get("/api/gif/<path:run_path>")
    def api_gif(run_path: str | None = None):
        requested_path = _requested_path(run_path)
        if not requested_path:
            return jsonify({"error": "Missing run path"}), 400
        run, run_dir = _get_known_run(requested_path)
        if run is None or run_dir is None:
            return jsonify({"error": "Run not found in the indexed runs root"}), 404
        return _serve_precomputed_or_generate(
            run_dir,
            "trajectory.gif",
            "generate_trajectory_gif",
            "create_trajectory_gif",
            "image/gif",
        )

    @app.get("/api/available_experiments")
    def api_available_experiments():
        exp_model_pairs: dict[str, set[str]] = {}
        for run in runs:
            exp_model_pairs.setdefault(run["experiment"], set()).add(run["model"])
        return jsonify(
            {"experiments": {exp: sorted(models) for exp, models in exp_model_pairs.items()}}
        )

    @app.post("/api/statistics")
    def api_statistics():
        data = request.get_json(silent=True) or {}
        pairs = data.get("pairs", [])
        if not pairs:
            return jsonify({"error": "No experiment-model pairs provided"}), 400
        experiment_model_pairs = [(pair["experiment"], pair["model"]) for pair in pairs]
        return jsonify(compare_experiments(experiment_model_pairs, base_path=str(resolved_root)))

    return app


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Trajectory dashboard for Gym-Anything runs.")
    parser.add_argument("--runs-root", default="all_runs", help="Root directory containing run artifacts.")
    parser.add_argument("--constraint", default=None, help="Optional substring filter for experiment names.")
    parser.add_argument("--host", default="127.0.0.1", help="Host interface to bind.")
    parser.add_argument("--port", type=int, default=5050, help="Port to bind.")
    parser.add_argument("--debug", action="store_true", help="Enable Flask debug mode.")
    args = parser.parse_args(argv)

    app = create_app(args.runs_root, constraint=args.constraint)
    print(f"Trajectory viewer serving {app.config['TRAJECTORY_RUNS_ROOT']}")
    print(f"Indexed {len(app.config['TRAJECTORY_RUNS'])} runs")
    if args.constraint:
        print(f"Constraint: {args.constraint}")
    print(f"Open http://{args.host}:{args.port}")
    app.run(host=args.host, port=args.port, debug=args.debug, use_reloader=False)


if __name__ == "__main__":
    main()
