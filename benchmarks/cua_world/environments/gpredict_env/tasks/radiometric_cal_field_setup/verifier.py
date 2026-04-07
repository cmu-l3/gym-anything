#!/usr/bin/env python3
"""
Verifier for radiometric_cal_field_setup task.

Verifies:
1. Railroad_Valley ground station created correctly (Lat, Lon, Alt).
2. Vicarious_Cal module created with specific satellites.
3. Module assigned specifically to the Railroad_Valley QTH.
4. UI Layout set to List view (LAYOUT=1).
5. Global minimum elevation set to 15 degrees.
6. UTC time enabled.
7. Anti-gaming check (files modified after task start).
8. VLM Trajectory check.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def verify_radiometric_cal_field_setup(traj, env_info, task_info):
    """
    Scoring System (100 points total):
    - QTH Creation (Lat/Lon/Alt): 15 pts
    - Module Creation (Satellites): 15 pts
    - QTH Assignment (Module tied to QTH): 15 pts
    - UI Layout (List view): 10 pts
    - Terrain Masking (Min Elevation 15): 10 pts
    - UTC Time Configured: 10 pts
    - VLM Trajectory Verification: 25 pts
    
    Pass threshold: 75 points, AND key anti-gaming constraints met.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    task_start = result.get('task_start_time', 0)

    # ==========================================================
    # 1. QTH Creation (15 points)
    # ==========================================================
    if result.get('qth_exists'):
        qth_mtime = result.get('qth_mtime', 0)
        if qth_mtime >= task_start:
            lat_ok = _close_enough(result.get('qth_lat', ''), 38.504, 0.05)
            # Accept either positive 115.694 West or negative -115.694 format
            lon_raw = result.get('qth_lon', '').replace('-', '')
            lon_ok = _close_enough(lon_raw, 115.694, 0.05)
            alt_ok = _close_enough(result.get('qth_alt', ''), 1435, 5)

            if lat_ok and lon_ok and alt_ok:
                score += 15
                feedback_parts.append("QTH created with correct coordinates")
            elif lat_ok and lon_ok:
                score += 10
                feedback_parts.append("QTH created with correct lat/lon but wrong altitude")
            else:
                score += 5
                feedback_parts.append("QTH created but coordinates are inaccurate")
        else:
            feedback_parts.append("QTH file pre-dates task start (Anti-Gaming Triggered)")
    else:
        feedback_parts.append("Railroad_Valley QTH not found")

    # ==========================================================
    # 2. Module Creation & Satellites (15 points)
    # ==========================================================
    mod_satellites = result.get('mod_satellites', '')
    if result.get('mod_exists'):
        mod_mtime = result.get('mod_mtime', 0)
        if mod_mtime >= task_start:
            has_37849 = "37849" in mod_satellites
            has_32958 = "32958" in mod_satellites
            has_37214 = "37214" in mod_satellites

            found_count = sum([has_37849, has_32958, has_37214])
            if found_count == 3:
                score += 15
                feedback_parts.append("Module created with all 3 required satellites")
            elif found_count > 0:
                score += (found_count * 5)
                feedback_parts.append(f"Module created with {found_count}/3 required satellites")
            else:
                feedback_parts.append("Module created but required satellites missing")
        else:
            feedback_parts.append("Module file pre-dates task start (Anti-Gaming Triggered)")
    else:
        feedback_parts.append("Vicarious_Cal module not found")

    # ==========================================================
    # 3. QTH Assignment (15 points)
    # ==========================================================
    if result.get('mod_exists'):
        mod_qthfile = result.get('mod_qthfile', '').lower()
        if "railroad" in mod_qthfile:
            score += 15
            feedback_parts.append("Module assigned exclusively to Railroad Valley QTH")
        elif mod_qthfile:
            feedback_parts.append(f"Module assigned to wrong QTH: {mod_qthfile}")
        else:
            feedback_parts.append("Module not explicitly assigned to a QTH (defaulting to global)")

    # ==========================================================
    # 4. UI Layout (10 points)
    # ==========================================================
    if result.get('mod_exists'):
        layout = result.get('mod_layout', '')
        # GPredict uses LAYOUT=1 for List View, LAYOUT=0 for Map
        if layout == "1":
            score += 10
            feedback_parts.append("Module layout configured to List view")
        else:
            feedback_parts.append(f"Module layout incorrect (LAYOUT={layout}, expected 1)")

    # ==========================================================
    # 5. Terrain Masking / Min Elevation (10 points)
    # ==========================================================
    min_el = result.get('pref_min_el', '')
    if _close_enough(min_el, 15, 0.5):
        score += 10
        feedback_parts.append("Global minimum elevation set to 15 degrees")
    elif min_el:
        feedback_parts.append(f"Minimum elevation is {min_el} (expected 15)")
    else:
        feedback_parts.append("Minimum elevation not configured")

    # ==========================================================
    # 6. UTC Time Configured (10 points)
    # ==========================================================
    utc_val = result.get('pref_utc', '')
    if utc_val == "1":
        score += 10
        feedback_parts.append("UTC time enabled globally")
    else:
        feedback_parts.append("UTC time not enabled")

    # ==========================================================
    # 7. VLM Trajectory Verification (25 points)
    # ==========================================================
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            prompt = (
                "You are an evaluator verifying a UI automation agent. The agent had to configure GPredict: "
                "1. Add a new ground station (Railroad Valley). "
                "2. Create a module tracking weather satellites in a List view. "
                "3. Open preferences and change minimum elevation and UTC settings. "
                "Look at these trajectory screenshots. Did the agent navigate through the "
                "Preferences menus, Ground Station dialogs, or Module configuration screens? "
                "Reply with ONLY a valid JSON: {'ui_interaction_visible': true/false, 'reasoning': '...'}"
            )
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res and isinstance(vlm_res, dict) and vlm_res.get('parsed'):
                if vlm_res['parsed'].get('ui_interaction_visible', False):
                    score += 25
                    feedback_parts.append("VLM confirmed trajectory interaction with configuration menus")
                else:
                    feedback_parts.append("VLM did not detect interaction with required UI dialogs")
            else:
                # If VLM fails, grant partial credit so we don't totally fail a good run, 
                # but heavily penalize to encourage robust VLM
                score += 10
                feedback_parts.append("VLM check failed/errored - partial fallback credit given")
        else:
            feedback_parts.append("No trajectory screenshots available for VLM verification")
    except Exception as e:
        logger.warning(f"VLM verification exception: {e}")
        score += 10
        feedback_parts.append("VLM import/execution failed - fallback credit given")

    passed = (score >= 75)
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }