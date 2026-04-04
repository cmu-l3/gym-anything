#!/usr/bin/env python3
"""Verifier for diagnose_station_anomaly_scrttv task.

A duty seismologist must identify a station producing anomalous data (GE.KWP),
disable its processing bindings in scconfig, and write a diagnostic report.

Scoring:
- 35 pts: KWP station bindings disabled (scautopick removed from key file)
- 25 pts: Other 4 stations still have their bindings intact (no collateral damage)
- 25 pts: Report file exists at correct path, names KWP as the problematic station
- 15 pts: Report describes both symptoms and corrective action taken

Wrong-target guards:
- If a wrong station was disabled, deduct points
- If no changes were made at all, return 0
"""

import json
import os
import tempfile


def verify_diagnose_station_anomaly_scrttv(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "diagnose_station_anomaly_scrttv"
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

    kwp_has_scautopick = _bool(result.get("kwp_has_scautopick", True))
    kwp_has_scamp = _bool(result.get("kwp_has_scamp", True))
    other_with_bindings = int(result.get("other_stations_with_bindings", 0))
    wrong_station_disabled = _bool(result.get("wrong_station_disabled", False))
    report_exists = _bool(result.get("report_exists", False))
    report_mentions_kwp = _bool(result.get("report_mentions_kwp", False))
    report_has_symptoms = _bool(result.get("report_has_symptoms", False))
    report_has_action = _bool(result.get("report_has_action", False))
    report_size = int(result.get("report_size", 0))

    # ── Do-nothing guard ───────────────────────────────────────────────────
    kwp_still_fully_bound = kwp_has_scautopick and kwp_has_scamp
    if kwp_still_fully_bound and not report_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "No changes detected. KWP still has all bindings and no report was written. "
                "The agent must inspect waveforms in scrttv, identify the anomalous station, "
                "disable its bindings in scconfig, and write a diagnostic report."
            ),
        }

    score = 0
    parts = []

    # ── Criterion 1 (35 pts): KWP bindings disabled ───────────────────────
    if not kwp_has_scautopick:
        score += 25
        parts.append("KWP scautopick binding removed (25/25)")
    else:
        parts.append("KWP still has scautopick binding — not disabled (0/25)")

    if not kwp_has_scamp:
        score += 10
        parts.append("KWP scamp binding also removed (10/10)")
    else:
        parts.append("KWP scamp binding still present (0/10)")

    # ── Criterion 2 (25 pts): Other stations untouched ────────────────────
    if other_with_bindings == 4 and not wrong_station_disabled:
        score += 25
        parts.append("All 4 other stations retain their bindings — no collateral damage (25/25)")
    elif wrong_station_disabled:
        # Penalize: a correct station was also disabled
        penalty = max(0, 25 - (4 - other_with_bindings) * 10)
        score += penalty
        parts.append(
            f"WARNING: A non-target station was also disabled. "
            f"Only {other_with_bindings}/4 other stations retain bindings ({penalty}/25)"
        )
    else:
        score += other_with_bindings * 6
        parts.append(
            f"{other_with_bindings}/4 other stations retain bindings "
            f"({other_with_bindings * 6}/25)"
        )

    # ── Criterion 3 (25 pts): Report exists and identifies KWP ────────────
    if report_exists and report_mentions_kwp and report_size >= 20:
        score += 25
        parts.append("Report exists, names KWP as problematic station (25/25)")
    elif report_exists and report_size >= 20:
        # Report exists but doesn't name KWP — partial credit
        score += 8
        parts.append(
            "Report exists but does not clearly identify KWP as the faulty station (8/25)"
        )
    elif report_exists:
        score += 5
        parts.append(f"Report exists but too short ({report_size} bytes) (5/25)")
    else:
        parts.append("No report file found at /home/ga/Desktop/station_anomaly_report.txt (0/25)")

    # ── Criterion 4 (15 pts): Report quality — symptoms + action ──────────
    if report_has_symptoms and report_has_action:
        score += 15
        parts.append("Report describes both symptoms and corrective action (15/15)")
    elif report_has_symptoms:
        score += 8
        parts.append("Report describes symptoms but not corrective action (8/15)")
    elif report_has_action:
        score += 5
        parts.append("Report describes corrective action but not symptoms (5/15)")
    else:
        parts.append("Report lacks description of symptoms and corrective action (0/15)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts),
    }
