#!/usr/bin/env python3
"""
Verifier for museum_kiosk_display task.

Verification Strategy:
1. MSI_Chicago Ground Station (15 pts): Coordinates match correctly.
2. Crewed_Missions Module (15 pts): Exists, contains ISS (25544) and CSS (48274).
3. QTH Assigned (10 pts): Module is bound to the MSI_Chicago QTH.
4. Layout is Map-Only (10 pts): SHOWMAP=1, and all others (SHOWEV, SHOWPOLARPLOT, SHOWSKYAT) are 0 or LAYOUT=3.
5. Amateur module closed (10 pts): Not present in GUI modules config.
6. Track Preferences Updated (15 pts): Checking config for track all (TRK_TYPE/ALL) and 2 orbits.
7. Fullscreen & Visual (25 pts): VLM verifies trajectory and final screenshot to ensure it's fullscreen and visual tracks are present.
"""

import json
import os
import re
import tempfile
import logging
import sys

# Framework provided VLM utility
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _close_enough(value_str, expected_float, tolerance=0.1):
    """Check if a string-encoded float is within tolerance of expected."""
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def verify_museum_kiosk_display(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    
    # --- Criterion 1: Ground Station (15 pts) ---
    if result.get('msi_exists', False):
        lat_ok = _close_enough(result.get('msi_lat'), metadata.get('qth_lat', 41.7906), 0.1)
        lon_ok = _close_enough(result.get('msi_lon'), metadata.get('qth_lon', -87.5830), 0.1)
        alt_ok = _close_enough(result.get('msi_alt'), metadata.get('qth_alt', 181), 20)
        
        # Check if created during task
        if result.get('msi_mtime', 0) >= task_start:
            if lat_ok and lon_ok and alt_ok:
                score += 15
                feedback_parts.append("MSI_Chicago ground station accurate.")
            else:
                score += 5
                feedback_parts.append("MSI_Chicago exists but coordinates/altitude are inaccurate.")
        else:
            feedback_parts.append("MSI_Chicago ground station was not created during this task.")
    else:
        feedback_parts.append("MSI_Chicago ground station NOT found.")

    # --- Criterion 2: Module Populated (15 pts) ---
    crewed_exists = result.get('crewed_exists', False)
    if crewed_exists:
        sats = result.get('crewed_satellites', '')
        has_iss = '25544' in sats
        has_css = '48274' in sats
        
        if has_iss and has_css:
            score += 15
            feedback_parts.append("Crewed_Missions module contains ISS and CSS.")
        elif has_iss or has_css:
            score += 7
            feedback_parts.append("Crewed_Missions module missing one station.")
        else:
            feedback_parts.append("Crewed_Missions exists but lacks required stations.")
    else:
        feedback_parts.append("Crewed_Missions module NOT found.")

    # --- Criterion 3: QTH Assigned (10 pts) ---
    if crewed_exists:
        qth_file = result.get('crewed_qthfile', '').lower()
        if 'msi' in qth_file or 'chicago' in qth_file:
            score += 10
            feedback_parts.append("Module QTH properly assigned.")
        else:
            feedback_parts.append(f"Module QTH assignment is wrong: {qth_file}")

    # --- Criterion 4: Map-Only Layout (10 pts) ---
    if crewed_exists:
        # Map-only is typically LAYOUT=3, or SHOWMAP=1 and others =0
        layout = result.get('crewed_layout', '')
        s_map = result.get('crewed_showmap', '')
        s_ev = result.get('crewed_showev', '')
        s_polar = result.get('crewed_showpolarplot', '')
        s_sky = result.get('crewed_showskyat', '')
        
        if layout == '3' or (s_map == '1' and s_ev == '0' and s_polar == '0' and s_sky == '0'):
            score += 10
            feedback_parts.append("Layout set to map-only.")
        else:
            feedback_parts.append("Layout is NOT map-only.")

    # --- Criterion 5: Amateur Module Closed (10 pts) ---
    gui_modules = result.get('gui_modules', '').lower()
    if 'amateur' not in gui_modules and 'crew' in gui_modules:
        score += 10
        feedback_parts.append("Amateur module closed successfully.")
    else:
        feedback_parts.append("Amateur module is still open or Crewed_Missions is not active.")

    # --- Criterion 6: Preferences Updated (15 pts) ---
    cfg = result.get('cfg_content', '')
    # Check for ground track orbits=2 and track all=true
    # In GPredict: TRK_ORB=2 (orbits) and TRK_TYPE=1 (all) or similar keys
    has_orbits = re.search(r'TRK_ORB=2', cfg, re.IGNORECASE) is not None
    # Track type: 1 = all, 0 = selected
    has_track_all = re.search(r'TRK_TYPE=1', cfg, re.IGNORECASE) is not None
    
    pref_score = 0
    if has_orbits:
        pref_score += 7
    if has_track_all:
        pref_score += 8
        
    score += pref_score
    if pref_score == 15:
        feedback_parts.append("Visual preferences (orbits & track-all) configured correctly.")
    elif pref_score > 0:
        feedback_parts.append("Visual preferences partially configured.")
    else:
        feedback_parts.append("Visual preferences (orbits & track-all) not found in cfg.")

    # --- Criterion 7: VLM & Fullscreen Verification (25 pts) ---
    vlm_score = 0
    if result.get('fullscreen_active', False):
        vlm_score += 10
        feedback_parts.append("Fullscreen mode detected programmatically.")
    
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            prompt = (
                "You are evaluating a GPredict UI configuration task for a museum kiosk. "
                "Look at the trajectory and the final screenshot. "
                "1. Is the application running in fullscreen (no OS window borders or taskbars visible)? "
                "2. Is the main UI displaying ONLY a large map (no lists, tables, or polar plots)? "
                "3. Are ground tracks (future orbit lines) visibly rendered on the map? "
                "Respond strictly in JSON: {\"is_fullscreen\": true/false, \"is_map_only\": true/false, \"has_ground_tracks\": true/false}"
            )
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if not result.get('fullscreen_active', False) and parsed.get('is_fullscreen'):
                    vlm_score += 10
                    feedback_parts.append("VLM verified fullscreen.")
                if parsed.get('is_map_only') and parsed.get('has_ground_tracks'):
                    vlm_score += 15
                    feedback_parts.append("VLM verified visual tracking elements.")
                else:
                    feedback_parts.append("VLM did not detect map-only view or ground tracks.")
            else:
                feedback_parts.append(f"VLM verification failed: {vlm_res.get('error')}")
        except Exception as e:
            feedback_parts.append(f"VLM exception: {e}")
    else:
        # If no VLM is available, grant points based on programmatic layout & config to avoid penalizing
        if pref_score == 15 and crewed_exists:
            vlm_score += 15
            feedback_parts.append("VLM unavailable. Bypassing visual track checks based on config.")
            
    score += min(vlm_score, 25)

    passed = score >= 70 and crewed_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }