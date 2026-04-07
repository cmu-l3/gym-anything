#!/usr/bin/env python3
"""
Verifier for radar_calibration_layout_setup task.

Verification Criteria:
1. Amateur module deleted (10 pts)
2. Millstone Hill QTH created with correct coordinates (20 pts)
3. Default QTH set to Millstone Hill (10 pts)
4. Radar_Cal module created with 4 required calibration satellites (25 pts)
5. Radar_Cal layout changed to "List Only" (SHOWMAP=0, SHOWPOLARPLOT=0) (20 pts)
6. Imperial Units enabled in preferences (15 pts)

Includes VLM visual verification as a secondary anti-gaming check.
"""

import json
import os
import tempfile
import logging

# Try to import VLM utilities for secondary verification
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_radar_calibration_layout_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []

    # Check anti-gaming timestamps (ensure changes happened after task start)
    start_time = result.get('task_start_time', 0)
    mod_time = result.get('config_modified_time', 0)
    if start_time > 0 and mod_time > 0 and mod_time < start_time:
        logger.warning(f"Config modification time ({mod_time}) is before task start time ({start_time}).")

    # 1. Amateur Module Deleted (10 pts)
    if result.get('amateur_deleted', False):
        score += 10
        feedback_parts.append("Amateur module successfully deleted")
    else:
        feedback_parts.append("Amateur module was NOT deleted")

    # 2. Millstone Hill QTH created correctly (20 pts)
    if result.get('millstone_exists', False):
        lat_ok = _close_enough(result.get('millstone_lat', ''), metadata.get('millstone_lat', 42.6195), 0.1)
        lon_ok = _close_enough(result.get('millstone_lon', ''), metadata.get('millstone_lon', -71.4903), 0.1)
        alt_ok = _close_enough(result.get('millstone_alt', ''), metadata.get('millstone_alt', 146), 10)

        if lat_ok and lon_ok and alt_ok:
            score += 20
            feedback_parts.append("Millstone Hill ground station correct")
        elif lat_ok and lon_ok:
            score += 15
            feedback_parts.append(f"Millstone Hill: coords OK but altitude wrong (got {result.get('millstone_alt')}m)")
        else:
            score += 5
            feedback_parts.append("Millstone Hill QTH found but coordinates incorrect")
    else:
        feedback_parts.append("Millstone Hill ground station NOT FOUND")

    # 3. Default QTH set to Millstone (10 pts)
    default_qth = result.get('default_qth', '')
    millstone_file = result.get('millstone_qth_file', 'Millstone_Hill.qth')
    if default_qth and default_qth.lower() == millstone_file.lower():
        score += 10
        feedback_parts.append("Default QTH successfully set to Millstone Hill")
    else:
        feedback_parts.append(f"Default QTH is '{default_qth}', expected '{millstone_file}'")

    # 4. Radar_Cal Module Satellites (25 pts)
    if result.get('radar_cal_exists', False):
        satellites_str = result.get('radar_cal_satellites', '')
        req_sats = metadata.get('required_satellites', [1314, 900, 902, 1313])
        found_sats = []
        missing_sats = []
        
        for sat in req_sats:
            if str(sat) in satellites_str:
                found_sats.append(str(sat))
            else:
                missing_sats.append(str(sat))
                
        if len(found_sats) == 4:
            score += 25
            feedback_parts.append("Radar_Cal module contains all 4 calibration spheres")
        else:
            partial_score = len(found_sats) * 6
            score += partial_score
            feedback_parts.append(f"Radar_Cal missing sats: {', '.join(missing_sats)}")
    else:
        feedback_parts.append("Radar_Cal module NOT FOUND")

    # 5. List-Only Layout configuration (20 pts)
    if result.get('radar_cal_exists', False):
        showmap = result.get('radar_cal_showmap', '1')
        showpolar = result.get('radar_cal_showpolar', '1')
        
        if showmap == "0" and showpolar == "0":
            score += 20
            feedback_parts.append("Radar_Cal layout correctly set to List Only (map and polar disabled)")
        else:
            feedback_parts.append(f"Radar_Cal layout incorrect (SHOWMAP={showmap}, SHOWPOLARPLOT={showpolar})")

    # 6. Imperial Units enabled (15 pts)
    if result.get('imperial_units_enabled', False):
        score += 15
        feedback_parts.append("Global units set to Imperial (miles)")
    else:
        feedback_parts.append("Global units NOT set to Imperial (still metric)")

    # VLM Secondary Check (Anti-gaming for Layout / UI configuration)
    vlm_feedback = ""
    if VLM_AVAILABLE and score >= 60:
        try:
            frames = sample_trajectory_frames(traj, n=2)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """
            Look at these screenshots of the GPredict satellite tracking software.
            1. Are the Map and circular Polar views completely disabled/hidden, leaving ONLY a tabular list of satellites visible taking up the main window?
            2. Does the distance/range column in the table show 'mi' (miles) instead of 'km'?
            
            Respond in JSON: {"list_only_view": true/false, "imperial_units_visible": true/false}
            """
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("list_only_view") and parsed.get("imperial_units_visible"):
                    vlm_feedback = "VLM confirmed List Only view and Imperial units."
                else:
                    vlm_feedback = "VLM could NOT confirm UI changes visually."
        except Exception as e:
            logger.error(f"VLM check failed: {e}")

    if vlm_feedback:
        feedback_parts.append(vlm_feedback)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }