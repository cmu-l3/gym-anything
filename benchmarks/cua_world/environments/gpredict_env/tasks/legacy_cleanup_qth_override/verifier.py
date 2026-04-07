#!/usr/bin/env python3
"""
Verifier for legacy_cleanup_qth_override task.

Task:
1. Delete TestModule1 and TestModule2
2. Keep Amateur module intact
3. Add White Sands, NM QTH (32.5007N, -106.6086W, 1219m)
4. Add Wallops Island, VA QTH (37.9402N, -75.4664W, 12m)
5. Create LEO_Comms module with 6 satellites (25544, 27607, 43017, 43137, 42761, 42759)
6. Set LEO_Comms module-specific QTH to White Sands
7. Set global default QTH to White Sands

Scoring (100 points, pass >= 70):
- TestModule1 deleted: 10 pts
- TestModule2 deleted: 10 pts
- Amateur.mod preserved: 5 pts
- LEO_Comms module exists: 5 pts
- LEO_Comms has 6 correct satellites (1 pt each): 6 pts
- LEO_Comms has White Sands QTH bound: 14 pts
- White Sands QTH created correctly: 20 pts
- Wallops Island QTH created correctly: 15 pts
- Global default QTH changed to White Sands: 15 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.1):
    """Check if a string-encoded float is within tolerance of expected."""
    try:
        if not value_str:
            return False
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_legacy_cleanup_qth_override(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/legacy_cleanup_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

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

    # 1 & 2. Module Deletions (20 pts)
    if not result.get('test1_exists', True):
        score += 10
        feedback_parts.append("TestModule1 deleted")
    else:
        feedback_parts.append("TestModule1 NOT deleted")

    if not result.get('test2_exists', True):
        score += 10
        feedback_parts.append("TestModule2 deleted")
    else:
        feedback_parts.append("TestModule2 NOT deleted")

    # 3. Preserve Amateur.mod (5 pts)
    if result.get('amateur_exists', False):
        score += 5
        feedback_parts.append("Amateur module preserved")
    else:
        feedback_parts.append("Amateur module inappropriately deleted")

    # 4. Create LEO_Comms module and populate (11 pts)
    leo_exists = result.get('leo_comms_exists', False)
    if leo_exists:
        score += 5
        feedback_parts.append("LEO_Comms module created")
        
        # Check Satellites (1 pt each, total 6)
        sat_str = result.get('leo_comms_satellites', '')
        req_sats = metadata.get('leo_comms_required_satellites', [25544, 27607, 43017, 43137, 42761, 42759])
        sats_found = 0
        for sat in req_sats:
            if str(sat) in sat_str:
                sats_found += 1
                score += 1
        feedback_parts.append(f"LEO_Comms has {sats_found}/{len(req_sats)} correct satellites")
    else:
        feedback_parts.append("LEO_Comms module NOT FOUND")

    # 5. Ground Stations Created (35 pts)
    ws_created = False
    ws_filename = result.get('ws_filename', '')
    if result.get('ws_exists'):
        lat_ok = _close_enough(result.get('ws_lat'), metadata.get('white_sands_lat', 32.5007), 0.1)
        lon_ok = _close_enough(result.get('ws_lon'), metadata.get('white_sands_lon', -106.6086), 0.1)
        alt_ok = _close_enough(result.get('ws_alt'), metadata.get('white_sands_alt', 1219), 50)
        
        if lat_ok and lon_ok and alt_ok:
            score += 20
            ws_created = True
            feedback_parts.append("White Sands QTH created correctly")
        elif lat_ok and lon_ok:
            score += 10
            ws_created = True
            feedback_parts.append("White Sands QTH created (altitude incorrect)")
        else:
            feedback_parts.append("White Sands QTH found but coords wrong")
    else:
        feedback_parts.append("White Sands QTH NOT FOUND")

    if result.get('wi_exists'):
        lat_ok = _close_enough(result.get('wi_lat'), metadata.get('wallops_island_lat', 37.9402), 0.1)
        lon_ok = _close_enough(result.get('wi_lon'), metadata.get('wallops_island_lon', -75.4664), 0.1)
        alt_ok = _close_enough(result.get('wi_alt'), metadata.get('wallops_island_alt', 12), 20)
        
        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("Wallops Island QTH created correctly")
        elif lat_ok and lon_ok:
            score += 7
            feedback_parts.append("Wallops Island QTH created (altitude incorrect)")
        else:
            feedback_parts.append("Wallops Island QTH found but coords wrong")
    else:
        feedback_parts.append("Wallops Island QTH NOT FOUND")

    # 6. Module-Specific QTH Override (14 pts)
    if leo_exists and ws_created:
        mod_qth = result.get('leo_comms_qthfile', '').strip().lower()
        if mod_qth and ws_filename and (ws_filename.lower() in mod_qth or 'white' in mod_qth):
            score += 14
            feedback_parts.append("Module-specific QTH override set to White Sands")
        else:
            feedback_parts.append(f"Module QTH not set correctly (is: {mod_qth})")
    elif leo_exists:
        feedback_parts.append("Cannot verify module QTH override (White Sands QTH missing)")

    # 7. Global Default QTH Changed (15 pts)
    default_qth = result.get('default_qth', '').strip().lower()
    if ws_created and ws_filename and (ws_filename.lower() in default_qth or ('white' in default_qth and 'sand' in default_qth)):
        score += 15
        feedback_parts.append("Global default QTH set to White Sands")
    else:
        feedback_parts.append(f"Global default QTH incorrect (is: {default_qth})")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }