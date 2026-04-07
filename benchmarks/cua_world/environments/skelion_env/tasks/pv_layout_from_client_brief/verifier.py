#!/usr/bin/env python3
"""
Verifier for pv_layout_from_client_brief task.

Scoring (100 pts total, pass >= 60):
  - Location set to San Francisco (lat 37.65-37.85, lon -122.55 to -122.25): 30 pts
  - At least 75 panels placed (panel_delta >= 75): 40 pts
  - PV_Layout_Report.csv exported to Desktop (exists, size > 100 bytes): 30 pts

Occupation context: Solar Energy Systems Engineer
"""

import json
import os


def verify_pv_layout_from_client_brief(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    # Pull result file from the VM
    result_path = "C:\\Users\\Docker\\pv_layout_result.json"
    local_tmp = "/tmp/pv_layout_result.json"

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
    csv_exists = bool(result.get("csv_exists", False))
    csv_size = int(result.get("csv_size_bytes", 0))
    csv_is_new = bool(result.get("csv_is_new", csv_exists))  # fallback for compat

    # --- Criterion 1: Location set to San Francisco ---
    SF_LAT_MIN, SF_LAT_MAX = 37.65, 37.85
    SF_LON_MIN, SF_LON_MAX = -122.55, -122.25
    if SF_LAT_MIN <= lat <= SF_LAT_MAX and SF_LON_MIN <= lon <= SF_LON_MAX:
        score += 30
        feedback_parts.append(f"Location OK: lat={lat:.4f}, lon={lon:.4f} (San Francisco)")
    else:
        feedback_parts.append(
            f"Location WRONG: lat={lat:.4f}, lon={lon:.4f} — expected SF range "
            f"lat[{SF_LAT_MIN},{SF_LAT_MAX}], lon[{SF_LON_MIN},{SF_LON_MAX}]"
        )

    # --- Criterion 2: At least 75 panels placed ---
    MIN_PANELS = 75
    if panel_delta >= MIN_PANELS:
        score += 40
        feedback_parts.append(f"Panels OK: {panel_delta} panels placed (minimum {MIN_PANELS})")
    elif panel_delta > 0:
        # Partial credit: proportional up to 20 pts
        partial = min(20, int(40 * panel_delta / MIN_PANELS))
        score += partial
        feedback_parts.append(
            f"Panels PARTIAL: {panel_delta} placed, need {MIN_PANELS} "
            f"(partial credit: {partial}/40)"
        )
    else:
        feedback_parts.append(f"Panels MISSING: 0 panels detected (need {MIN_PANELS})")

    # --- Criterion 3: CSV report exported ---
    if csv_exists and csv_size > 100:
        score += 30
        feedback_parts.append(f"CSV OK: PV_Layout_Report.csv exists ({csv_size} bytes)")
    elif csv_exists:
        score += 10
        feedback_parts.append(
            f"CSV PARTIAL: file exists but very small ({csv_size} bytes, may be empty)"
        )
    else:
        feedback_parts.append("CSV MISSING: PV_Layout_Report.csv not found on Desktop")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
