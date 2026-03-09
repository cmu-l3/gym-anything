#!/usr/bin/env python3
"""
Verifier for classify_and_reorganize_satellites task (Very Hard).

Task: Audit and fix misconfigured GPredict Amateur module:
  1. Identify 4 weather satellites mixed into Amateur.mod and REMOVE them:
     - SUOMI NPP (37849), FENGYUN 3A (32958), FENGYUN 3B (37214), DMSP F18 (35951)
  2. Create a WeatherSats module containing all 4 removed weather satellites
  3. Add Fairbanks AK ground station (64.8378N, 147.7164W, 133m)
  4. Enable metric units

Scoring (100 points, pass >= 60 — lower threshold due to discovery difficulty):
  - Each weather sat removed from Amateur: 10 pts × 4 = 40 pts
  - Each weather sat in WeatherSats module: 10 pts × 4 = 40 pts
  - Fairbanks AK ground station: 15 pts
  - Metric units enabled: 5 pts
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def _check_metric_units(result):
    if result.get('metric_units_enabled'):
        return True
    cfg_content = result.get('gpredict_cfg_content', '')
    if cfg_content:
        if re.search(r'unit\s*=\s*0', cfg_content):
            return True
    return False


def verify_classify_and_reorganize_satellites(traj, env_info, task_info):
    """
    Verify the satellite classification and reorganization task (Very Hard).

    Scoring (100 points, pass >= 60):
    - SUOMI NPP (37849) removed from Amateur: 10 pts
    - FENGYUN 3A (32958) removed from Amateur: 10 pts
    - FENGYUN 3B (37214) removed from Amateur: 10 pts
    - DMSP F18 (35951) removed from Amateur: 10 pts
    - SUOMI NPP in WeatherSats: 10 pts
    - FENGYUN 3A in WeatherSats: 10 pts
    - FENGYUN 3B in WeatherSats: 10 pts
    - DMSP F18 in WeatherSats: 10 pts
    - Fairbanks AK ground station: 15 pts
    - Metric units enabled: 5 pts

    Pass threshold: 60 (lower due to very hard classification challenge)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/classify_and_reorganize_satellites_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0,
                    "feedback": f"Could not copy result file: {e}"}

        with open(temp_path, 'r') as f:
            result = json.load(f)

    except (json.JSONDecodeError, FileNotFoundError) as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        try:
            os.unlink(temp_path)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    removed_from_amateur = []
    still_in_amateur = []
    in_weathersats = []
    missing_from_weathersats = []

    # Weather satellite checks: [result_key_amateur_still_has, result_key_ws_has, norad, name]
    weather_sats = [
        ('amateur_still_has_suomi', 'ws_has_suomi', 37849, 'SUOMI NPP'),
        ('amateur_still_has_fy3a', 'ws_has_fy3a', 32958, 'FENGYUN 3A'),
        ('amateur_still_has_fy3b', 'ws_has_fy3b', 37214, 'FENGYUN 3B'),
        ('amateur_still_has_dmsp', 'ws_has_dmsp', 35951, 'DMSP F18'),
    ]

    for amateur_key, ws_key, norad, name in weather_sats:
        # Points for removing from Amateur (10 pts each)
        still_in_amateur_flag = result.get(amateur_key, True)  # default True = not removed
        if not still_in_amateur_flag:
            score += 10
            removed_from_amateur.append(f"{name} ({norad})")
        else:
            still_in_amateur.append(f"{name} ({norad})")

        # Points for being in WeatherSats (10 pts each)
        in_ws_flag = result.get(ws_key, False)
        if in_ws_flag:
            score += 10
            in_weathersats.append(f"{name} ({norad})")
        else:
            missing_from_weathersats.append(f"{name} ({norad})")

    # Build feedback for removal criterion
    if removed_from_amateur:
        feedback_parts.append(f"Removed from Amateur: {', '.join(removed_from_amateur)}")
    if still_in_amateur:
        feedback_parts.append(f"Still in Amateur (should be removed): {', '.join(still_in_amateur)}")

    # Build feedback for WeatherSats criterion
    if not result.get('weathersats_exists'):
        feedback_parts.append("WeatherSats module: NOT FOUND (no module with 'weather' or 'wx' in name)")
    else:
        feedback_parts.append(f"WeatherSats module found: '{result.get('weathersats_mod_name')}'")
        if in_weathersats:
            feedback_parts.append(f"In WeatherSats: {', '.join(in_weathersats)}")
        if missing_from_weathersats:
            feedback_parts.append(f"Missing from WeatherSats: {', '.join(missing_from_weathersats)}")

    # --- Fairbanks AK ground station (15 pts) ---
    if result.get('fairbanks_exists'):
        lat_ok = _close_enough(result.get('fairbanks_lat', ''), metadata.get('fairbanks_lat', 64.8378), 0.1)
        lon_ok = _close_enough(result.get('fairbanks_lon', ''), metadata.get('fairbanks_lon', -147.7164), 0.1)
        alt_ok = _close_enough(result.get('fairbanks_alt', ''), metadata.get('fairbanks_alt', 133), 20)

        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("Fairbanks AK ground station: correct")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append(f"Fairbanks AK: coordinates OK but altitude off ({result.get('fairbanks_alt')}m, expected 133m)")
        else:
            score += 5
            feedback_parts.append(f"Fairbanks AK exists but coordinates wrong (lat={result.get('fairbanks_lat')})")
    else:
        feedback_parts.append("Fairbanks AK ground station: NOT FOUND")

    # --- Metric units (5 pts) ---
    if _check_metric_units(result):
        score += 5
        feedback_parts.append("Metric units: enabled")
    else:
        feedback_parts.append("Metric units: NOT enabled")

    # Lower pass threshold (60) for very hard discovery task
    passed = score >= 60

    all_removed = not any([
        result.get('amateur_still_has_suomi'),
        result.get('amateur_still_has_fy3a'),
        result.get('amateur_still_has_fy3b'),
        result.get('amateur_still_has_dmsp'),
    ])
    all_in_ws = all([
        result.get('ws_has_suomi'),
        result.get('ws_has_fy3a'),
        result.get('ws_has_fy3b'),
        result.get('ws_has_dmsp'),
    ])

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "weather_sats_removed_from_amateur": all_removed,
            "weather_sats_in_weathersats_module": all_in_ws,
            "weathersats_module_exists": result.get('weathersats_exists', False),
            "fairbanks_station": result.get('fairbanks_exists', False),
            "metric_units": _check_metric_units(result),
        }
    }
