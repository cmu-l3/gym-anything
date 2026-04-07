#!/usr/bin/env python3
"""
Verifier for permit_package_preparation task.

Scoring (100 pts total, pass >= 60):
  - Location set to New York City (lat 40.50-40.90, lon -74.20 to -73.80): 25 pts
  - Panel count 60-150 placed (panel_delta in [60, 150]): 35 pts
    - Partial: any panels placed (1-59 or 151+): up to 15 pts
  - Permit_Ready.skp saved on Desktop (exists, size > 50 KB): 40 pts

Occupation context: Solar Energy Systems Engineer — NYC permit package preparation
"""

import json


def verify_permit_package_preparation(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    result_path = "C:\\Users\\Docker\\permit_package_result.json"
    local_tmp = "/tmp/permit_package_result.json"

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
    permit_exists = bool(result.get("permit_file_exists", False))
    permit_size = int(result.get("permit_file_size", 0))
    permit_is_new = bool(result.get("permit_file_is_new", permit_exists))  # fallback for compat

    # Also check working model in case agent didn't Save As but placed panels
    working_lat = float(result.get("working_model_lat", lat))
    working_lon = float(result.get("working_model_lon", lon))
    working_delta = int(result.get("working_panel_delta", panel_delta))

    # --- Criterion 1: Location set to New York City ---
    NYC_LAT_MIN, NYC_LAT_MAX = 40.50, 40.90
    NYC_LON_MIN, NYC_LON_MAX = -74.20, -73.80

    # Check both final model (Permit_Ready.skp) and working model
    final_in_nyc = NYC_LAT_MIN <= lat <= NYC_LAT_MAX and NYC_LON_MIN <= lon <= NYC_LON_MAX
    working_in_nyc = (
        NYC_LAT_MIN <= working_lat <= NYC_LAT_MAX
        and NYC_LON_MIN <= working_lon <= NYC_LON_MAX
    )

    if final_in_nyc or working_in_nyc:
        score += 25
        check_lat = lat if final_in_nyc else working_lat
        check_lon = lon if final_in_nyc else working_lon
        feedback_parts.append(
            f"Location OK: lat={check_lat:.4f}, lon={check_lon:.4f} (New York City)"
        )
    else:
        feedback_parts.append(
            f"Location WRONG: lat={lat:.4f}, lon={lon:.4f} — expected NYC "
            f"lat[{NYC_LAT_MIN},{NYC_LAT_MAX}], lon[{NYC_LON_MIN},{NYC_LON_MAX}]"
        )

    # --- Criterion 2: Panel count 60-150 ---
    MIN_PANELS, MAX_PANELS = 60, 150
    effective_delta = max(panel_delta, working_delta)

    if MIN_PANELS <= effective_delta <= MAX_PANELS:
        score += 35
        feedback_parts.append(
            f"Panels OK: {effective_delta} panels placed (required: {MIN_PANELS}-{MAX_PANELS})"
        )
    elif effective_delta > MAX_PANELS:
        # Too many panels — partial credit (exceeds structural load limit)
        score += 15
        feedback_parts.append(
            f"Panels OVER LIMIT: {effective_delta} placed (max {MAX_PANELS} allowed for permit) — partial credit"
        )
    elif effective_delta > 0:
        # Some panels placed but not enough
        partial = min(15, int(35 * effective_delta / MIN_PANELS))
        score += partial
        feedback_parts.append(
            f"Panels PARTIAL: {effective_delta} placed, need {MIN_PANELS}-{MAX_PANELS} "
            f"(partial: {partial}/35)"
        )
    else:
        feedback_parts.append(
            f"Panels MISSING: 0 panels detected (need {MIN_PANELS}-{MAX_PANELS})"
        )

    # --- Criterion 3: Permit_Ready.skp saved on Desktop ---
    # SketchUp .skp files are at minimum ~30 KB for a model with content
    MIN_SIZE_BYTES = 50_000
    if permit_exists and permit_size >= MIN_SIZE_BYTES:
        score += 40
        feedback_parts.append(
            f"Permit_Ready.skp OK: file exists on Desktop ({permit_size:,} bytes)"
        )
    elif permit_exists and permit_size > 0:
        score += 15
        feedback_parts.append(
            f"Permit_Ready.skp EXISTS but small ({permit_size:,} bytes, expected >= {MIN_SIZE_BYTES:,}) — "
            "may be an empty/invalid save"
        )
    else:
        feedback_parts.append(
            "Permit_Ready.skp MISSING: file not found on Desktop — "
            "agent must use File > Save As to create this file"
        )

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
