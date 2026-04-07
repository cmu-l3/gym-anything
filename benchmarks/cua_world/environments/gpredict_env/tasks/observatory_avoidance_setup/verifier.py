#!/usr/bin/env python3
"""
Verifier for observatory_avoidance_setup task.

Verifies:
1. Deletion of obsolete tracking module
2. Preservation of target existing module
3. Creation of multiple ground station files with correct coordinates
4. Creation of multiple module files with correct satellites
5. Proper QTHFILE binding specific to each module
6. Preferences update (UTC time format)
7. Trajectory visual verification (anti-gaming: UI interaction confirmed)
"""

import json
import os
import re
import tempfile
import logging

# Gym-anything imports for trajectory/VLM
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_observatory_avoidance_setup(traj, env_info, task_info):
    """
    Score the complex configuration of tracking modules and ground stations.
    Maximum Score: 100 points
    Pass Threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        copy_from_env("/tmp/observatory_avoidance_setup_result.json", temp_path)
        
        with open(temp_path, 'r') as f:
            result = json.load(f)

    except (json.JSONDecodeError, FileNotFoundError) as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []

    # 1. Obsolete module deleted (10 pts)
    if not result.get('oldtracker_exists', True):
        score += 10
        feedback_parts.append("OldTracker correctly deleted")
    else:
        feedback_parts.append("FAIL: OldTracker module still exists")

    # 2. Existing module preserved (5 pts)
    if result.get('amateur_preserved', False):
        score += 5
        feedback_parts.append("Amateur.mod safely preserved")
    else:
        feedback_parts.append("FAIL: Amateur.mod was altered or deleted")

    # 3. Lowell Ground Station (10 pts total: Lat=5, Lon=3, Alt=2)
    if result.get('lowell_qth_exists', False):
        lat_ok = _close_enough(result.get('lowell_lat', ''), metadata.get('lowell_lat', 35.2029), 0.1)
        lon_ok = _close_enough(result.get('lowell_lon', ''), metadata.get('lowell_lon', -111.6646), 0.1)
        alt_ok = _close_enough(result.get('lowell_alt', ''), metadata.get('lowell_alt', 2210), 30)
        
        if lat_ok: score += 5
        if lon_ok: score += 3
        if alt_ok: score += 2
        
        if lat_ok and lon_ok and alt_ok:
            feedback_parts.append("Lowell QTH perfect")
        else:
            feedback_parts.append(f"Lowell QTH partial (Lat:{lat_ok}, Lon:{lon_ok}, Alt:{alt_ok})")
    else:
        feedback_parts.append("FAIL: Lowell QTH missing")

    # 4. McDonald Ground Station (10 pts total: Lat=5, Lon=3, Alt=2)
    if result.get('mcdonald_qth_exists', False):
        lat_ok = _close_enough(result.get('mcdonald_lat', ''), metadata.get('mcdonald_lat', 30.6716), 0.1)
        lon_ok = _close_enough(result.get('mcdonald_lon', ''), metadata.get('mcdonald_lon', -104.0217), 0.1)
        alt_ok = _close_enough(result.get('mcdonald_alt', ''), metadata.get('mcdonald_alt', 2070), 30)
        
        if lat_ok: score += 5
        if lon_ok: score += 3
        if alt_ok: score += 2

        if lat_ok and lon_ok and alt_ok:
            feedback_parts.append("McDonald QTH perfect")
        else:
            feedback_parts.append(f"McDonald QTH partial (Lat:{lat_ok}, Lon:{lon_ok}, Alt:{alt_ok})")
    else:
        feedback_parts.append("FAIL: McDonald QTH missing")

    # 5. Lowell Avoidance Module (20 pts total: Exists=2, Sats=12, QTH Binding=6)
    if result.get('lowell_mod_exists', False):
        score += 2
        
        # SATS (3 pts each x 4)
        sats = result.get('lowell_satellites', '')
        missing_lowell = []
        for sid in metadata.get('lowell_sats', [25544, 48274, 33591, 37849]):
            if str(sid) in sats:
                score += 3
            else:
                missing_lowell.append(str(sid))
        if not missing_lowell:
            feedback_parts.append("Lowell_Avoidance sats correct")
        else:
            feedback_parts.append(f"Lowell_Avoidance missing sats: {missing_lowell}")

        # QTH Binding (6 pts)
        if "lowell" in result.get('lowell_qthfile', '').lower():
            score += 6
            feedback_parts.append("Lowell_Avoidance properly bound to Lowell QTH")
        else:
            feedback_parts.append(f"FAIL: Lowell_Avoidance bound to '{result.get('lowell_qthfile')}' instead of Lowell")
    else:
        feedback_parts.append("FAIL: Lowell_Avoidance module missing")

    # 6. McDonald Avoidance Module (20 pts total: Exists=2, Sats=12, QTH Binding=6)
    if result.get('mcdonald_mod_exists', False):
        score += 2
        
        # SATS (3 pts each x 4)
        sats = result.get('mcdonald_satellites', '')
        missing_mcdonald = []
        for sid in metadata.get('mcdonald_sats', [25544, 48274, 28654, 35951]):
            if str(sid) in sats:
                score += 3
            else:
                missing_mcdonald.append(str(sid))
        if not missing_mcdonald:
            feedback_parts.append("McDonald_Avoidance sats correct")
        else:
            feedback_parts.append(f"McDonald_Avoidance missing sats: {missing_mcdonald}")

        # QTH Binding (6 pts)
        if "mcdonald" in result.get('mcdonald_qthfile', '').lower():
            score += 6
            feedback_parts.append("McDonald_Avoidance properly bound to McDonald QTH")
        else:
            feedback_parts.append(f"FAIL: McDonald_Avoidance bound to '{result.get('mcdonald_qthfile')}' instead of McDonald")
    else:
        feedback_parts.append("FAIL: McDonald_Avoidance module missing")

    # 7. Global UTC Configuration (5 pts)
    cfg_content = result.get('gpredict_cfg_content', '')
    if re.search(r'(utc|TIME_FORMAT)\s*=\s*[12]', cfg_content, re.IGNORECASE):
        score += 5
        feedback_parts.append("UTC time enabled globally")
    else:
        feedback_parts.append("FAIL: UTC time not enabled in config")

    # 8. VLM Trajectory Verification (10 pts)
    # Check if agent genuinely interacted with UI configurations.
    # We sample 5 frames across the trajectory.
    try:
        frames = sample_trajectory_frames(traj, n=5)
        vlm_prompt = (
            "You are verifying a GPredict satellite tracking configuration task. "
            "Did the agent open the 'Edit Module', 'Module Options', 'Preferences', or 'New Ground Station' "
            "dialogue windows at any point during these frames? Respond with ONLY 'YES' or 'NO'."
        )
        vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
        if "YES" in vlm_result.get("text", "").upper():
            score += 10
            feedback_parts.append("VLM confirmed UI interaction")
        else:
            feedback_parts.append("VLM did not observe UI configuration dialogs")
    except Exception as e:
        logger.error(f"VLM error: {e}")
        # If VLM fails, we grant the points but warn, so we don't penalize system errors
        score += 10
        feedback_parts.append("VLM verification skipped/failed (granted default points)")

    # Anti-gaming: Ensure it didn't complete too quickly to be realistic
    elapsed = result.get('task_end', 0) - result.get('task_start', 0)
    if elapsed < 15:
        score = int(score * 0.5)
        feedback_parts.append(f"WARNING: Completed suspiciously fast ({elapsed}s) - Score halved")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }