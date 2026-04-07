#!/usr/bin/env python3
"""
Verifier for net_zero_system_design task.

Scoring (100 pts total, pass >= 60):
  - Location set to Austin, TX (lat 30.10-30.60, lon -98.10 to -97.50): 30 pts
  - At least 63 panels placed (panel_delta >= 63): 35 pts
  - System_Sizing_Report.txt exists on Desktop (size > 50 bytes): 25 pts
    + up to 10 bonus pts for report containing required sections
    (total capped at 100)

Occupation context: Energy Engineer — net-zero commercial building design
"""

import json
import re


def verify_net_zero_system_design(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    result_path = "C:\\Users\\Docker\\net_zero_result.json"
    local_tmp = "/tmp/net_zero_result.json"

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

    # --- Criterion 1: Location set to Austin, TX ---
    AUS_LAT_MIN, AUS_LAT_MAX = 30.10, 30.60
    AUS_LON_MIN, AUS_LON_MAX = -98.10, -97.50
    if AUS_LAT_MIN <= lat <= AUS_LAT_MAX and AUS_LON_MIN <= lon <= AUS_LON_MAX:
        score += 30
        feedback_parts.append(f"Location OK: lat={lat:.4f}, lon={lon:.4f} (Austin, TX)")
    else:
        feedback_parts.append(
            f"Location WRONG: lat={lat:.4f}, lon={lon:.4f} — expected Austin "
            f"lat[{AUS_LAT_MIN},{AUS_LAT_MAX}], lon[{AUS_LON_MIN},{AUS_LON_MAX}]"
        )

    # --- Criterion 2: At least 63 panels placed ---
    MIN_PANELS = 63
    if panel_delta >= MIN_PANELS:
        score += 35
        feedback_parts.append(f"Panels OK: {panel_delta} placed (minimum {MIN_PANELS})")
    elif panel_delta > 0:
        partial = min(18, int(35 * panel_delta / MIN_PANELS))
        score += partial
        feedback_parts.append(
            f"Panels PARTIAL: {panel_delta} placed, need {MIN_PANELS} (partial: {partial}/35)"
        )
    else:
        feedback_parts.append(f"Panels MISSING: 0 panels detected (need {MIN_PANELS})")

    # --- Criterion 3: System_Sizing_Report.txt ---
    if report_exists and report_size > 50:
        score += 25
        feedback_parts.append(f"Report EXISTS: {report_size} bytes")
        # Bonus for required content sections
        content_lower = report_content.lower()
        bonus = 0
        has_location = bool(re.search(r"30\.\d|97\.\d|austin", content_lower))
        has_panels = bool(re.search(r"\d+\s*panel|\bpanel\w*\s*\d+", content_lower))
        has_energy = bool(re.search(r"kwh|kw|generat|annual|produc", content_lower))
        has_feasibility = bool(re.search(r"net.zero|feasib|achiev|viab", content_lower))
        if has_location:
            bonus += 3
            feedback_parts.append("Report has location info")
        if has_panels:
            bonus += 3
            feedback_parts.append("Report mentions panels")
        if has_energy:
            bonus += 2
            feedback_parts.append("Report has energy figures")
        if has_feasibility:
            bonus += 2
            feedback_parts.append("Report has feasibility statement")
        score = min(100, score + bonus)
    elif report_exists:
        score += 8
        feedback_parts.append(
            f"Report PARTIAL: file exists but very small ({report_size} bytes)"
        )
    else:
        feedback_parts.append("Report MISSING: System_Sizing_Report.txt not found on Desktop")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
