#!/usr/bin/env python3
"""
Verifier for a_train_constellation_tracking task.

Task: Configure GPredict to monitor the A-Train Earth Observing Constellation.
  1. Delete default Amateur module.
  2. Create GSFC_Goddard ground station (38.9951 N, 76.8505 W, 50m).
  3. Create A_Train module tracking: AQUA (27424), AURA (28376), OCO-2 (40059), GCOM-W1 (38337).
  4. Bind A_Train module to GSFC_Goddard ground station.
  5. Enable Ground Tracks visually.

Scoring (100 points, pass >= 75):
  - Amateur module deleted: 10 pts
  - GSFC_Goddard ground station created with correct coords: 20 pts
  - A_Train module created: 10 pts
  - A_Train tracks all 4 correct satellites: 20 pts
  - A_Train QTH bound to GSFC_Goddard: 20 pts
  - VLM Verification: Map visually displays ground track orbit lines: 20 pts
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any

# Assuming framework provides these in the real environment
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Dummy fallbacks for local testing
    def sample_trajectory_frames(traj, n=3): return []
    def get_final_screenshot(traj): return None
    def query_vlm(images, prompt): return {"success": True, "parsed": {"ground_track_visible": True}}

logger = logging.getLogger(__name__)

def _close_enough(value_str, expected_float, tolerance=0.15):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

VLM_PROMPT = """You are evaluating the success of a satellite tracking task in GPredict.
Please examine the provided screenshots (trajectory and final state) to verify if the user successfully enabled Ground Tracks.

Check the map interface carefully.
Is there a solid line drawn across the Earth map that extends from or ahead of the satellites, representing their orbital path (Ground Track)? 
Often this looks like a curved trajectory line spanning across continents/oceans attached to the satellite icons.

Respond in strict JSON format:
{
    "ground_track_visible": true/false,
    "reasoning": "Brief explanation of what you observe"
}
"""

def verify_a_train_constellation_tracking(traj, env_info, task_info):
    """
    Verify the A-Train tracking configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        copy_from_env("/tmp/a_train_result.json", temp_path)

        with open(temp_path, 'r') as f:
            result = json.load(f)

    except (json.JSONDecodeError, FileNotFoundError, Exception) as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []

    # --- Criterion 1: Amateur module deleted (10 pts) ---
    if not result.get('amateur_exists', True):
        score += 10
        feedback_parts.append("Amateur module successfully deleted")
    else:
        feedback_parts.append("Amateur module STILL EXISTS (should be deleted)")

    # --- Criterion 2: GSFC Ground Station (20 pts) ---
    if result.get('gsfc_exists'):
        lat_ok = _close_enough(result.get('gsfc_lat', ''), metadata.get('gsfc_lat', 38.9951), 0.1)
        lon_ok = _close_enough(result.get('gsfc_lon', ''), metadata.get('gsfc_lon', -76.8505), 0.1)
        alt_ok = _close_enough(result.get('gsfc_alt', ''), metadata.get('gsfc_alt', 50), 20)

        if lat_ok and lon_ok and alt_ok:
            score += 20
            feedback_parts.append("GSFC ground station correct")
        elif lat_ok and lon_ok:
            score += 15
            feedback_parts.append("GSFC ground station exists but altitude slightly off")
        else:
            score += 5
            feedback_parts.append(f"GSFC ground station found but coords off (Lat: {result.get('gsfc_lat')}, Lon: {result.get('gsfc_lon')})")
    else:
        feedback_parts.append("GSFC ground station NOT FOUND")

    # --- Criterion 3: A_Train Module Exists (10 pts) ---
    if result.get('a_train_exists'):
        score += 10
        feedback_parts.append("A_Train module created")
    else:
        feedback_parts.append("A_Train module NOT FOUND")

    # --- Criterion 4: A_Train Satellites (20 pts) ---
    if result.get('a_train_exists'):
        sats_found = []
        sats_missing = []
        has_aqua = result.get('a_train_has_aqua', False)
        has_aura = result.get('a_train_has_aura', False)
        has_oco2 = result.get('a_train_has_oco2', False)
        has_gcom = result.get('a_train_has_gcom', False)

        if has_aqua: sats_found.append("AQUA")
        else: sats_missing.append("AQUA")
        
        if has_aura: sats_found.append("AURA")
        else: sats_missing.append("AURA")
        
        if has_oco2: sats_found.append("OCO-2")
        else: sats_missing.append("OCO-2")
        
        if has_gcom: sats_found.append("GCOM-W1")
        else: sats_missing.append("GCOM-W1")

        sat_count = len(sats_found)
        if sat_count == 4:
            score += 20
            feedback_parts.append("A_Train tracks all 4 required satellites")
        elif sat_count > 0:
            score += (sat_count * 5)
            feedback_parts.append(f"A_Train has {sat_count}/4 satellites. Missing: {', '.join(sats_missing)}")
        else:
            feedback_parts.append("A_Train has no required satellites")

    # --- Criterion 5: QTH Binding (20 pts) ---
    if result.get('a_train_exists') and result.get('gsfc_exists'):
        bound_qth = result.get('a_train_qthfile', '').strip()
        expected_qth = result.get('gsfc_filename', '').strip()
        
        # Checking if it matches the newly created GSFC file
        if bound_qth and expected_qth and bound_qth.lower() == expected_qth.lower():
            score += 20
            feedback_parts.append(f"A_Train correctly bound to {expected_qth}")
        else:
            feedback_parts.append(f"A_Train bound to '{bound_qth}', expected '{expected_qth}'")
    elif result.get('a_train_exists'):
        feedback_parts.append(f"A_Train bound to '{result.get('a_train_qthfile')}' but GSFC QTH missing")

    # --- Criterion 6: VLM Ground Track Check (20 pts) ---
    try:
        frames = sample_trajectory_frames(traj, n=3)
        final_img = get_final_screenshot(traj)
        if final_img:
            images = frames + [final_img]
            vlm_res = query_vlm(images=images, prompt=VLM_PROMPT)
            
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("ground_track_visible", False):
                    score += 20
                    feedback_parts.append("VLM confirmed Ground Tracks are visible")
                else:
                    feedback_parts.append("VLM did not detect visible Ground Tracks")
            else:
                # Fallback to config check if VLM fails
                cfg_tracks = "SHOWTRACK=1" in result.get("mod_track_settings", "").upper() or \
                             "TRACK_VISIBLE" in result.get("global_track_settings", "").upper()
                if cfg_tracks:
                    score += 10
                    feedback_parts.append("Config suggests Ground Tracks enabled (VLM query failed, partial credit)")
                else:
                    feedback_parts.append("VLM query failed and no Ground Track config found")
        else:
            feedback_parts.append("No screenshots available for VLM check")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback_parts.append("VLM verification exception occurred")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }