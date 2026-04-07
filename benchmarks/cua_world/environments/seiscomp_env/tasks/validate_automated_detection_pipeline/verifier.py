#!/usr/bin/env python3
"""Verifier for validate_automated_detection_pipeline task.

Scoring (stub — VLM checklist verifier will be used for final evaluation):
- 15 pts: Station bindings configured (scautopick on 3 target stations)
- 10 pts: scautopick config has bandpass filter setting
- 20 pts: Automatic picks generated in database (at least 1 per station)
- 10 pts: At least one automatic origin generated in database
- 10 pts: Validation script exists and is valid Python
- 15 pts: JSON report exists with correct structure
- 20 pts: JSON report contains plausible data (pick counts, distances)

Pass threshold: 60/100
"""

import json
import os
import tempfile


def verify_validate_automated_detection_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "validate_automated_detection_pipeline"
    result_path = f"/tmp/{task_name}_result.json"

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(result_path, tmp.name)
            with open(tmp.name, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export_result.sh may not have run",
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file is not valid JSON: {e}",
        }

    def _bool(v):
        if isinstance(v, bool):
            return v
        return str(v).lower() == "true"

    stations_with_scautopick = int(result.get("stations_with_scautopick", 0))
    has_scautopick_cfg = _bool(result.get("has_scautopick_cfg", False))
    scautopick_filter = str(result.get("scautopick_filter", ""))
    auto_pick_count = int(result.get("auto_pick_count", 0))
    picks_gsi = int(result.get("picks_gsi", 0))
    picks_bkb = int(result.get("picks_bkb", 0))
    picks_sani = int(result.get("picks_sani", 0))
    auto_origin_count = int(result.get("auto_origin_count", 0))
    script_exists = _bool(result.get("script_exists", False))
    script_is_valid_python = _bool(result.get("script_is_valid_python", False))
    script_created_during_task = _bool(result.get("script_created_during_task", False))
    report_exists = _bool(result.get("report_exists", False))
    report_is_valid_json = _bool(result.get("report_is_valid_json", False))
    report_created_during_task = _bool(result.get("report_created_during_task", False))
    report_has_pick_count = _bool(result.get("report_has_pick_count", False))
    report_has_origin_count = _bool(result.get("report_has_origin_count", False))
    report_has_origin_lat = _bool(result.get("report_has_origin_lat", False))
    report_has_origin_lon = _bool(result.get("report_has_origin_lon", False))
    report_has_station_picks = _bool(result.get("report_has_station_picks", False))
    report_pick_count = int(result.get("report_pick_count", 0))
    report_station_count = int(result.get("report_station_count", 0))

    # ── Do-nothing guard ─────────────────────────────────────────────────────
    if (
        stations_with_scautopick == 0
        and auto_pick_count == 0
        and not script_exists
        and not report_exists
        and not has_scautopick_cfg
    ):
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "No progress detected. No bindings configured, no picks generated, "
                "no validation script or report created."
            ),
        }

    score = 0
    parts = []

    # ── Criterion 1 (15 pts): Station bindings ───────────────────────────────
    if stations_with_scautopick >= 3:
        score += 15
        parts.append(f"scautopick bindings on {stations_with_scautopick} stations (15/15)")
    elif stations_with_scautopick >= 1:
        pts = stations_with_scautopick * 5
        score += pts
        parts.append(
            f"scautopick bindings on only {stations_with_scautopick}/3 stations ({pts}/15)"
        )
    else:
        parts.append("No scautopick station bindings configured (0/15)")

    # ── Criterion 2 (10 pts): scautopick config with filter ──────────────────
    if has_scautopick_cfg and "BW" in scautopick_filter.upper():
        score += 10
        parts.append("scautopick.cfg with bandpass filter (10/10)")
    elif has_scautopick_cfg:
        score += 5
        parts.append("scautopick.cfg exists but no BW filter found (5/10)")
    else:
        parts.append("No scautopick.cfg found (0/10)")

    # ── Criterion 3 (20 pts): Automatic picks generated ─────────────────────
    stations_with_picks = sum(1 for p in [picks_gsi, picks_bkb, picks_sani] if p > 0)
    if auto_pick_count >= 3 and stations_with_picks >= 3:
        score += 20
        parts.append(
            f"{auto_pick_count} automatic picks on {stations_with_picks} stations (20/20)"
        )
    elif auto_pick_count >= 1 and stations_with_picks >= 2:
        score += 14
        parts.append(
            f"{auto_pick_count} picks on {stations_with_picks} stations (14/20)"
        )
    elif auto_pick_count >= 1:
        score += 7
        parts.append(
            f"{auto_pick_count} picks on {stations_with_picks} station(s) (7/20)"
        )
    else:
        parts.append("No automatic picks generated (0/20)")

    # ── Criterion 4 (10 pts): Automatic origin generated ────────────────────
    if auto_origin_count >= 1:
        score += 10
        parts.append(f"{auto_origin_count} automatic origin(s) (10/10)")
    else:
        parts.append("No automatic origin generated (0/10)")

    # ── Criterion 5 (10 pts): Validation script ─────────────────────────────
    if script_exists and script_is_valid_python and script_created_during_task:
        score += 10
        parts.append("Validation script exists and is valid Python (10/10)")
    elif script_exists and script_created_during_task:
        score += 6
        parts.append("Validation script exists but has syntax errors (6/10)")
    elif script_exists:
        score += 3
        parts.append("Validation script exists but predates task (3/10)")
    else:
        parts.append("No validation script at /home/ga/validate_pipeline.py (0/10)")

    # ── Criterion 6 (15 pts): JSON report structure ──────────────────────────
    required_fields = [
        report_has_pick_count,
        report_has_origin_count,
        report_has_origin_lat,
        report_has_origin_lon,
        report_has_station_picks,
    ]
    fields_present = sum(1 for f in required_fields if f)

    if report_exists and report_is_valid_json and fields_present >= 5:
        score += 15
        parts.append("JSON report has all required fields (15/15)")
    elif report_exists and report_is_valid_json and fields_present >= 3:
        score += 10
        parts.append(f"JSON report has {fields_present}/5 required fields (10/15)")
    elif report_exists and report_is_valid_json:
        score += 5
        parts.append(f"JSON report valid but missing fields ({fields_present}/5) (5/15)")
    elif report_exists:
        score += 2
        parts.append("Report file exists but is not valid JSON (2/15)")
    else:
        parts.append("No JSON report at /home/ga/pipeline_report.json (0/15)")

    # ── Criterion 7 (20 pts): JSON report data plausibility ──────────────────
    if report_exists and report_is_valid_json and report_has_station_picks:
        plausibility_score = 0

        # Pick count should be >= 3 (one per station)
        if report_pick_count >= 3:
            plausibility_score += 7
        elif report_pick_count >= 1:
            plausibility_score += 3

        # Station picks array should have entries
        if report_station_count >= 3:
            plausibility_score += 7
        elif report_station_count >= 1:
            plausibility_score += 3

        # Origin coordinates should exist and be non-zero
        try:
            rlat = float(result.get("report_origin_lat", 0) or 0)
            rlon = float(result.get("report_origin_lon", 0) or 0)
            if rlat != 0 and rlon != 0:
                plausibility_score += 6
        except (ValueError, TypeError):
            pass

        score += plausibility_score
        parts.append(f"Report data plausibility ({plausibility_score}/20)")
    elif report_exists and report_is_valid_json:
        score += 3
        parts.append("Report valid JSON but no station_picks array (3/20)")
    else:
        parts.append("Cannot assess report data plausibility (0/20)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts),
    }
