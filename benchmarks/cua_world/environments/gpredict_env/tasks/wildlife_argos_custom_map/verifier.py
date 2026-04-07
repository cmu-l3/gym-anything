#!/usr/bin/env python3
"""
Verifier for wildlife_argos_custom_map task.

Task Requirements:
1. Custom map files installed to ~/.config/Gpredict/maps/
2. GPredict MAP config updated to "Ocean Bathymetry"
3. GPredict DRAW_GRID config updated to disabled (false/0)
4. Galapagos ground station correctly added (Lat -0.7420, Lon -90.3139, Alt 10)
5. Galapagos set as DEFAULT_QTH
6. Argos_Network module contains 6 required satellites
7. VLM check ensures UI reflects these states

Scoring Breakdown (100 pts total):
- Map File Installed: 10 pts
- UI Map Configuration Updated: 10 pts
- Grid Lines Disabled: 10 pts
- Galapagos Ground Station correct: 15 pts
- Galapagos set as Default QTH: 5 pts
- Argos Module configured (5 pts per satellite): 30 pts
- VLM Visual Verification (Map change & UI state): 20 pts

Pass Threshold: 75 pts
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_wildlife_argos_custom_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_sats = metadata.get('argos_satellites', [25338, 28654, 33591, 38771, 43689, 39086])

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/task_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []

    # 1. Map Files Installed (10 pts)
    if result.get('map_png_exists') and result.get('map_info_exists'):
        score += 10
        feedback_parts.append("Custom map files installed correctly")
    elif result.get('map_dir_exists') and (result.get('map_png_exists') or result.get('map_info_exists')):
        score += 5
        feedback_parts.append("Custom map files partially installed")
    else:
        feedback_parts.append("Custom map files NOT installed")

    # 2. Map Config Updated (10 pts)
    map_setting = result.get('map_setting', '')
    if "ocean bathymetry" in map_setting.lower():
        score += 10
        feedback_parts.append("Map configuration updated to Ocean Bathymetry")
    else:
        feedback_parts.append(f"Map config incorrect (current: '{map_setting}')")

    # 3. Grid Config Disabled (10 pts)
    grid_setting = result.get('grid_setting', '')
    if grid_setting in ['0', 'false', 'no']:
        score += 10
        feedback_parts.append("Map grid lines successfully disabled")
    else:
        feedback_parts.append(f"Map grid lines still enabled (current: '{grid_setting}')")

    # 4. Galapagos Station (15 pts)
    if result.get('galapagos_exists'):
        lat_ok = _close_enough(result.get('galapagos_lat', ''), metadata.get('galapagos_lat', -0.7420), 0.05)
        lon_ok = _close_enough(result.get('galapagos_lon', ''), metadata.get('galapagos_lon', -90.3139), 0.05)
        alt_ok = _close_enough(result.get('galapagos_alt', ''), metadata.get('galapagos_alt', 10), 10)

        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("Galapagos ground station coordinates correct")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append("Galapagos coordinates correct, altitude incorrect")
        else:
            score += 5
            feedback_parts.append("Galapagos station exists but coordinates are incorrect")
    else:
        feedback_parts.append("Galapagos ground station NOT FOUND")

    # 5. Default QTH (5 pts)
    default_qth = result.get('default_qth', '').lower()
    if "galapagos" in default_qth:
        score += 5
        feedback_parts.append("Default QTH correctly set to Galapagos")
    else:
        feedback_parts.append("Default QTH is not set to Galapagos")

    # 6. Argos Module (30 pts, 5 per sat)
    if result.get('argos_exists'):
        # Check anti-gaming
        task_start = result.get('task_start_time', 0)
        argos_mtime = result.get('argos_mtime', 0)
        if argos_mtime > 0 and argos_mtime >= task_start:
            argos_sats = result.get('argos_satellites', '')
            found_sats = 0
            missing_sats = []
            for sat in expected_sats:
                if str(sat) in argos_sats:
                    found_sats += 1
                    score += 5
                else:
                    missing_sats.append(str(sat))
            
            feedback_parts.append(f"Argos module: found {found_sats}/6 satellites")
            if missing_sats:
                feedback_parts.append(f"Argos missing: {', '.join(missing_sats)}")
        else:
            feedback_parts.append("Argos module exists but timestamp predates task start (invalid)")
    else:
        feedback_parts.append("Argos_Network module NOT FOUND")

    # 7. VLM Visual Verification (20 pts)
    # Ensure agent actually applied changes in the GUI (or restarted GPredict) 
    # and didn't just edit config files behind the back of a running process
    frames = sample_trajectory_frames(traj, n=3)
    final_img = get_final_screenshot(traj)
    images_to_check = frames + [final_img] if final_img else frames

    if images_to_check:
        prompt = """You are evaluating if a user successfully configured the GPredict satellite tracking software interface.
        Look closely at the trajectory and the final screenshots provided.

        Requirements:
        1. Is the map background a solid light blue/deep sky blue color (the custom bathymetry map) rather than the default multicolored political earth map?
        2. Are the latitude/longitude grid lines over the map hidden or disabled?
        3. Is there a module tab named "Argos_Network" or similar active?

        Return a JSON response:
        {
            "custom_map_visible": true/false,
            "grid_lines_disabled": true/false,
            "argos_tab_visible": true/false
        }
        """

        vlm_result = query_vlm(images=images_to_check, prompt=prompt)
        parsed = vlm_result.get("parsed", {})
        
        vlm_score = 0
        if parsed.get("custom_map_visible", False):
            vlm_score += 10
            feedback_parts.append("VLM: Custom map visible in UI")
        if parsed.get("grid_lines_disabled", False):
            vlm_score += 5
            feedback_parts.append("VLM: Grid lines disabled in UI")
        if parsed.get("argos_tab_visible", False):
            vlm_score += 5
            feedback_parts.append("VLM: Argos tab visible in UI")
            
        score += vlm_score
        
        if vlm_score == 0:
            feedback_parts.append("VLM: UI does not appear to reflect the required changes")
    else:
        feedback_parts.append("VLM Verification Skipped: No images available")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }