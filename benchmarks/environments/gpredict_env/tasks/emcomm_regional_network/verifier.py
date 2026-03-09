#!/usr/bin/env python3
"""
Verifier for emcomm_regional_network task.

Task: Configure GPredict for Pennsylvania RACES regional network:
  1. Fix Pittsburgh.qth altitude (450 -> 230m) and WX code (KXXX -> KPIT)
  2. Add Erie PA ground station (42.1292 N, 80.0851 W, 222m)
  3. Add Harrisburg PA ground station (40.2732 N, 76.8867 W, 102m)
  4. Complete RACES.mod with ISS (25544), SO-50 (27607), AO-85 (40967)

Scoring (100 points, pass >= 70):
  - Pittsburgh altitude corrected to 230m:       20 pts
  - Pittsburgh WX code = KPIT:                   10 pts
  - Erie QTH exists with correct LAT/LON/ALT:    25 pts
  - Harrisburg QTH exists with correct LAT/LON/ALT: 25 pts
  - RACES module has all 3 required satellites:  20 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.05):
    """Check if a string-encoded float is within tolerance of expected."""
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_emcomm_regional_network(traj, env_info, task_info):
    """
    Verify the EMCOMM regional network configuration task.

    Scoring (100 points):
    - Pittsburgh altitude corrected (ALT=230): 20 pts
    - Pittsburgh WX code correct (KPIT): 10 pts
    - Erie QTH exists with correct coordinates: 25 pts
    - Harrisburg QTH exists with correct coordinates: 25 pts
    - RACES module contains all 3 required satellites: 20 pts

    Pass threshold: 70 points
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
            copy_from_env("/tmp/emcomm_regional_network_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0,
                    "feedback": f"Could not copy result file: {e}. Was the task run?"}

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

    # --- Criterion 1: Pittsburgh altitude corrected (20 pts) ---
    pittsburgh_alt_str = result.get('pittsburgh_alt', '')
    correct_alt = metadata.get('pittsburgh_correct_alt', 230)
    wrong_alt = metadata.get('pittsburgh_incorrect_alt', 450)

    if _close_enough(pittsburgh_alt_str, correct_alt, tolerance=2):
        score += 20
        feedback_parts.append(f"Pittsburgh altitude corrected to {correct_alt}m")
    elif _close_enough(pittsburgh_alt_str, wrong_alt, tolerance=2):
        feedback_parts.append(f"Pittsburgh altitude still incorrect ({pittsburgh_alt_str}m, expected {correct_alt}m)")
    else:
        feedback_parts.append(f"Pittsburgh altitude: {pittsburgh_alt_str} (expected {correct_alt}m)")

    # --- Criterion 2: Pittsburgh WX code (10 pts) ---
    pittsburgh_wx = result.get('pittsburgh_wx', '').strip().upper()
    correct_wx = metadata.get('pittsburgh_correct_wx', 'KPIT').upper()

    if pittsburgh_wx == correct_wx:
        score += 10
        feedback_parts.append(f"Pittsburgh WX code correct ({correct_wx})")
    else:
        feedback_parts.append(f"Pittsburgh WX code: '{pittsburgh_wx}' (expected '{correct_wx}')")

    # --- Criterion 3: Erie ground station (25 pts) ---
    if result.get('erie_exists'):
        erie_lat_ok = _close_enough(result.get('erie_lat', ''), metadata.get('erie_lat', 42.1292), 0.05)
        erie_lon_ok = _close_enough(result.get('erie_lon', ''), metadata.get('erie_lon', -80.0851), 0.05)
        erie_alt_ok = _close_enough(result.get('erie_alt', ''), metadata.get('erie_alt', 222), 10)

        if erie_lat_ok and erie_lon_ok and erie_alt_ok:
            score += 25
            feedback_parts.append("Erie PA ground station: correct")
        elif erie_lat_ok and erie_lon_ok:
            score += 15
            feedback_parts.append(f"Erie PA: coordinates OK but altitude off ({result.get('erie_alt')}m, expected 222m)")
        else:
            score += 5
            feedback_parts.append(
                f"Erie PA exists but coordinates wrong "
                f"(lat={result.get('erie_lat')}, lon={result.get('erie_lon')})"
            )
    else:
        feedback_parts.append("Erie PA ground station: NOT FOUND")

    # --- Criterion 4: Harrisburg ground station (25 pts) ---
    if result.get('harrisburg_exists'):
        harr_lat_ok = _close_enough(result.get('harrisburg_lat', ''), metadata.get('harrisburg_lat', 40.2732), 0.05)
        harr_lon_ok = _close_enough(result.get('harrisburg_lon', ''), metadata.get('harrisburg_lon', -76.8867), 0.05)
        harr_alt_ok = _close_enough(result.get('harrisburg_alt', ''), metadata.get('harrisburg_alt', 102), 10)

        if harr_lat_ok and harr_lon_ok and harr_alt_ok:
            score += 25
            feedback_parts.append("Harrisburg PA ground station: correct")
        elif harr_lat_ok and harr_lon_ok:
            score += 15
            feedback_parts.append(f"Harrisburg PA: coordinates OK but altitude off ({result.get('harrisburg_alt')}m, expected 102m)")
        else:
            score += 5
            feedback_parts.append(
                f"Harrisburg PA exists but coordinates wrong "
                f"(lat={result.get('harrisburg_lat')}, lon={result.get('harrisburg_lon')})"
            )
    else:
        feedback_parts.append("Harrisburg PA ground station: NOT FOUND")

    # --- Criterion 5: RACES module contains all 3 satellites (20 pts) ---
    if result.get('races_exists'):
        has_iss = result.get('races_has_iss', False)
        has_so50 = result.get('races_has_so50', False)
        has_ao85 = result.get('races_has_ao85', False)

        sats_present = sum([has_iss, has_so50, has_ao85])

        if sats_present == 3:
            score += 20
            feedback_parts.append("RACES module: all 3 satellites present (ISS, SO-50, AO-85)")
        elif sats_present == 2:
            score += 12
            missing = []
            if not has_iss:
                missing.append("ISS (25544)")
            if not has_so50:
                missing.append("SO-50 (27607)")
            if not has_ao85:
                missing.append("AO-85 (40967)")
            feedback_parts.append(f"RACES module: 2/3 satellites present, missing: {', '.join(missing)}")
        elif sats_present == 1:
            score += 5
            feedback_parts.append("RACES module: only 1/3 required satellites present")
        else:
            feedback_parts.append("RACES module exists but missing all required satellites")
    else:
        feedback_parts.append("RACES module: NOT FOUND (no .mod file with 'RACE' in name)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "pittsburgh_altitude": _close_enough(result.get('pittsburgh_alt', ''), 230, 2),
            "pittsburgh_wx": result.get('pittsburgh_wx', '').strip().upper() == 'KPIT',
            "erie_station": result.get('erie_exists', False),
            "harrisburg_station": result.get('harrisburg_exists', False),
            "races_module_complete": result.get('races_has_iss') and result.get('races_has_so50') and result.get('races_has_ao85'),
        }
    }
