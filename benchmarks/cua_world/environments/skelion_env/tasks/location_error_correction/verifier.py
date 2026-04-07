#!/usr/bin/env python3
"""
Verifier for location_error_correction task.

Setup pre-seeds London, UK (lat≈51.5, lon≈-0.13) into shadow_info.
Agent must correct to Atlanta, GA and add at least 50 panels.

Scoring (100 pts total, pass >= 60):
  - Location corrected away from London (lon NOT in [-0.30, 0.10]): 20 pts
  - Location set to Atlanta, GA (lat 33.50-34.00, lon -84.60 to -84.10): 40 pts
    (includes the 20 pts above; i.e., only 40 total for location if Atlanta)
  - At least 50 panels placed (panel_delta >= 50): 40 pts
  - Wrong location (London not removed): 0 for location criteria

Occupation context: Solar Sales Representative — error correction workflow
"""

import json


def verify_location_error_correction(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    result_path = "C:\\Users\\Docker\\location_correction_result.json"
    local_tmp = "/tmp/location_correction_result.json"

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

    # London seeded coordinates (what setup put in)
    LONDON_LAT_MIN, LONDON_LAT_MAX = 51.00, 52.00
    LONDON_LON_MIN, LONDON_LON_MAX = -0.30, 0.10

    # Atlanta target coordinates
    ATL_LAT_MIN, ATL_LAT_MAX = 33.50, 34.00
    ATL_LON_MIN, ATL_LON_MAX = -84.60, -84.10

    is_still_london = (
        LONDON_LAT_MIN <= lat <= LONDON_LAT_MAX and LONDON_LON_MIN <= lon <= LONDON_LON_MAX
    )
    is_atlanta = (
        ATL_LAT_MIN <= lat <= ATL_LAT_MAX and ATL_LON_MIN <= lon <= ATL_LON_MAX
    )

    # --- Criterion 1 & 2: Location correction ---
    if is_atlanta:
        score += 40
        feedback_parts.append(
            f"Location CORRECTED to Atlanta: lat={lat:.4f}, lon={lon:.4f}"
        )
    elif not is_still_london and lat != 0.0:
        # Changed from London but not exactly Atlanta — partial credit
        score += 15
        feedback_parts.append(
            f"Location CHANGED from London but not Atlanta: lat={lat:.4f}, lon={lon:.4f} "
            f"(expected lat[{ATL_LAT_MIN},{ATL_LAT_MAX}], lon[{ATL_LON_MIN},{ATL_LON_MAX}])"
        )
    elif is_still_london:
        feedback_parts.append(
            f"Location NOT CORRECTED: still London lat={lat:.4f}, lon={lon:.4f} "
            f"(must change to Atlanta lat 33.7490 N, lon 84.3880 W)"
        )
    else:
        feedback_parts.append(
            f"Location UNKNOWN: lat={lat:.4f}, lon={lon:.4f} — expected Atlanta coordinates"
        )

    # --- Criterion 3: At least 50 panels placed ---
    MIN_PANELS = 50
    if panel_delta >= MIN_PANELS:
        score += 40
        feedback_parts.append(f"Panels OK: {panel_delta} panels placed (minimum {MIN_PANELS})")
    elif panel_delta > 0:
        partial = min(20, int(40 * panel_delta / MIN_PANELS))
        score += partial
        feedback_parts.append(
            f"Panels PARTIAL: {panel_delta} placed, need {MIN_PANELS} (partial: {partial}/40)"
        )
    else:
        feedback_parts.append(f"Panels MISSING: 0 panels detected (need {MIN_PANELS})")

    # Bonus: reward if London was correctly identified and fixed (20 pts if Atlanta + panels)
    if is_atlanta and panel_delta >= MIN_PANELS:
        score = min(100, score + 20)
        feedback_parts.append("Bonus: Full correction verified (London removed, Atlanta set, panels placed)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts),
    }
