#!/usr/bin/env python3
"""
Verifier for shadow_study_panel_placement task.

Scoring (100 pts total, pass >= 60):
  - Location set to Denver, CO (lat 39.40-39.80, lon -105.20 to -104.60): 30 pts
  - At least 40 panels placed (panel_delta >= 40): 35 pts
  - Shadow_Analysis_Report.txt exists on Desktop (size > 50 bytes): 35 pts
    Bonus: report contains site coordinates and panel count keywords: up to 10 pts
    (but total capped at 100)

Occupation context: Solar Installation Manager — Colorado school district
"""

import json
import re


def verify_shadow_study_panel_placement(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    result_path = "C:\\Users\\Docker\\shadow_study_result.json"
    local_tmp = "/tmp/shadow_study_result.json"

    try:
        copy_fn = env_info.get("copy_from_env")
        if copy_fn is None:
            return {"passed": False, "score": 0, "feedback": "No copy_from_env in env_info"}
        copy_fn(result_path, local_tmp)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found (export script may not have run): {e}",
        }

    try:
        with open(local_tmp, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}

    lat = float(result.get("latitude", 0.0))
    lon = float(result.get("longitude", 0.0))
    panel_delta = int(result.get("panel_delta", 0))
    report_exists = bool(result.get("report_exists", False))
    report_size = int(result.get("report_size_bytes", 0))
    report_is_new = bool(result.get("report_is_new", report_exists))  # fallback for compat
    report_content = str(result.get("report_content", "")).replace("\\n", "\n").replace("\\t", "\t")

    # --- Criterion 1: Location set to Denver, CO ---
    DEN_LAT_MIN, DEN_LAT_MAX = 39.40, 39.80
    DEN_LON_MIN, DEN_LON_MAX = -105.20, -104.60
    if DEN_LAT_MIN <= lat <= DEN_LAT_MAX and DEN_LON_MIN <= lon <= DEN_LON_MAX:
        score += 30
        feedback_parts.append(f"Location OK: lat={lat:.4f}, lon={lon:.4f} (Denver, CO)")
    else:
        feedback_parts.append(
            f"Location WRONG: lat={lat:.4f}, lon={lon:.4f} — expected Denver "
            f"lat[{DEN_LAT_MIN},{DEN_LAT_MAX}], lon[{DEN_LON_MIN},{DEN_LON_MAX}]"
        )

    # --- Criterion 2: At least 40 panels placed ---
    MIN_PANELS = 40
    if panel_delta >= MIN_PANELS:
        score += 35
        feedback_parts.append(f"Panels OK: {panel_delta} panels placed (minimum {MIN_PANELS})")
    elif panel_delta > 0:
        partial = min(18, int(35 * panel_delta / MIN_PANELS))
        score += partial
        feedback_parts.append(
            f"Panels PARTIAL: {panel_delta} placed, need {MIN_PANELS} (partial: {partial}/35)"
        )
    else:
        feedback_parts.append(f"Panels MISSING: 0 panels detected (need {MIN_PANELS})")

    # --- Criterion 3: Shadow_Analysis_Report.txt ---
    if report_exists and report_size > 50:
        base_report_score = 25
        score += base_report_score
        feedback_parts.append(
            f"Report EXISTS: {report_size} bytes"
        )
        # Bonus: check for required content keywords
        content_lower = report_content.lower()
        bonus = 0
        has_coords = bool(
            re.search(r"39\.\d|104\.\d", report_content)
        )
        has_panel_count = bool(re.search(r"\d+\s*panel|\bpanel\w*\s*\d+", content_lower))
        has_shading = bool(re.search(r"shad|shadow|solar|irradianc", content_lower))
        if has_coords:
            bonus += 4
            feedback_parts.append("Report has coordinates")
        if has_panel_count:
            bonus += 3
            feedback_parts.append("Report mentions panel count")
        if has_shading:
            bonus += 3
            feedback_parts.append("Report discusses solar/shading")
        score = min(100, score + bonus)
    elif report_exists:
        score += 10
        feedback_parts.append(
            f"Report PARTIAL: file exists but very small ({report_size} bytes)"
        )
    else:
        feedback_parts.append("Report MISSING: Shadow_Analysis_Report.txt not found on Desktop")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
