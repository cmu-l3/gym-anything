#!/usr/bin/env python3
"""
Verifier for historical_anomaly_playback task.

Scoring (100 points, pass >= 70):
1. Tromsø QTH File: Exists with correct coords/altitude (20 pts)
2. Module Config: Incident_Recon exists, tracks 37849 & 35951, assigned to Tromsø QTH (20 pts)
3. UTC Time: Enabled in preferences (5 pts)
4. Evidence: Screenshot saved to /home/ga/incident_reconstruction.png (5 pts)
5. VLM: Time Controller open and paused/manual mode (20 pts)
6. VLM: Time Controller set to Feb 28, 2026, 14:30 UTC (30 pts)
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_historical_anomaly_playback(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    # ================================================================
    # Extract file-based results
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/historical_anomaly_playback_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []

    # Criterion 1: Tromsø QTH (20 pts)
    tromso_exists = result.get('tromso_exists', False)
    if tromso_exists:
        lat_ok = _close_enough(result.get('tromso_lat', ''), metadata.get('tromso_lat', 69.6625), 0.1)
        lon_ok = _close_enough(result.get('tromso_lon', ''), metadata.get('tromso_lon', 18.9408), 0.1)
        alt_ok = _close_enough(result.get('tromso_alt', ''), metadata.get('tromso_alt', 130), 10)

        if lat_ok and lon_ok and alt_ok:
            score += 20
            feedback_parts.append("Tromsø QTH properly configured")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append(f"Tromsø QTH has wrong altitude ({result.get('tromso_alt')}m)")
        else:
            score += 5
            feedback_parts.append(f"Tromsø QTH coordinates imprecise")
    else:
        feedback_parts.append("Tromsø QTH NOT FOUND")

    # Criterion 2: Incident_Recon Module (20 pts)
    module_exists = result.get('module_exists', False)
    tromso_qth_name = result.get('tromso_qth_name', 'Tromso.qth')
    
    if module_exists:
        has_suomi = result.get('module_has_suomi', False)
        has_dmsp = result.get('module_has_dmsp', False)
        mod_qth = result.get('module_qthfile', '')

        sat_pts = 0
        if has_suomi: sat_pts += 5
        if has_dmsp: sat_pts += 5
        score += sat_pts

        if has_suomi and has_dmsp:
            feedback_parts.append("Module has required satellites")
        else:
            feedback_parts.append("Module missing required satellites")

        # Check QTH assignment
        if tromso_exists and (tromso_qth_name.lower() in mod_qth.lower() or 'tromso' in mod_qth.lower()):
            score += 10
            feedback_parts.append("Module assigned to Tromsø QTH")
        else:
            feedback_parts.append(f"Module QTH assignment wrong (is '{mod_qth}', expected '{tromso_qth_name}')")
    else:
        feedback_parts.append("Incident_Recon module NOT FOUND")

    # Criterion 3: UTC Time (5 pts)
    if result.get('utc_time_enabled', False):
        score += 5
        feedback_parts.append("UTC time enabled")
    else:
        feedback_parts.append("UTC time NOT enabled")

    # Criterion 4: Evidence File Exists (5 pts)
    evidence_exists = result.get('evidence_exists', False)
    evidence_size = int(result.get('evidence_size', 0))
    created_during = result.get('evidence_created_during_task', False)

    if evidence_exists and created_during and evidence_size > 10000:
        score += 5
        feedback_parts.append("Evidence screenshot saved correctly")
    elif evidence_exists:
        feedback_parts.append("Evidence screenshot found but timestamp/size invalid")
    else:
        feedback_parts.append("Evidence screenshot NOT saved to specified path")

    # ================================================================
    # VLM Verification: Time Controller State
    # ================================================================
    # We copy the agent's explicit screenshot to inspect it too, fallback to trajectory
    agent_img_path = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    agent_img_copied = False
    try:
        copy_from_env("/home/ga/incident_reconstruction.png", agent_img_path)
        if os.path.exists(agent_img_path) and os.path.getsize(agent_img_path) > 10000:
            agent_img_copied = True
    except Exception:
        pass

    images_to_check = []
    if agent_img_copied:
        images_to_check.append(agent_img_path)
    else:
        # Fallback to trajectory frames
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images_to_check = frames + [final] if final else frames
        
    vlm_prompt = """
    Look at the provided screenshot(s) of a GPredict satellite tracking session.
    Analyze the UI state, specifically looking for the 'Time Controller' window.
    
    Answer the following questions:
    1. Is the 'Time Controller' dialog clearly open and visible?
    2. Is the time controller paused? (Look for 'Use real time' being UNCHECKED, or a pause/stop button active indicating manual time).
    3. Is the simulation date set to February 28, 2026 (2026/02/28 or similar)?
    4. Is the simulation time set to exactly 14:30 (or 14:30:00)?
    5. Does the UI indicate it is displaying UTC time (often shown next to the time as UTC, or top right)?
    
    Respond STRICTLY in JSON format with boolean values:
    {
        "time_controller_visible": true/false,
        "is_paused": true/false,
        "date_is_feb_28_2026": true/false,
        "time_is_14_30": true/false,
        "is_utc": true/false,
        "reasoning": "Brief explanation of what you see"
    }
    """

    vlm_result = {"time_controller_visible": False, "is_paused": False, "date_is_feb_28_2026": False, "time_is_14_30": False}
    if images_to_check:
        try:
            vlm_response = query_vlm(prompt=vlm_prompt, images=images_to_check)
            if vlm_response and "parsed" in vlm_response:
                vlm_result = vlm_response["parsed"]
                logger.info(f"VLM Response: {vlm_result}")
            else:
                logger.warning("VLM failed to return parsable response")
        except Exception as e:
            logger.error(f"VLM Error: {e}")

    # Criterion 5: Controller Paused (20 pts)
    if vlm_result.get('time_controller_visible') and vlm_result.get('is_paused'):
        score += 20
        feedback_parts.append("VLM: Time controller visible and paused")
    else:
        feedback_parts.append("VLM: Time controller not visible or not paused")

    # Criterion 6: Controller exact Date/Time (30 pts)
    date_ok = vlm_result.get('date_is_feb_28_2026', False)
    time_ok = vlm_result.get('time_is_14_30', False)
    
    if date_ok and time_ok:
        score += 30
        feedback_parts.append("VLM: Time set correctly (2026-02-28 14:30)")
    elif date_ok or time_ok:
        score += 15
        feedback_parts.append("VLM: Time partially correct (either date or time matches)")
    else:
        feedback_parts.append("VLM: Target date/time not detected in UI")
        
    # Cleanup agent image
    if agent_img_copied and os.path.exists(agent_img_path):
        os.unlink(agent_img_path)

    # Final logic
    key_criteria_met = (tromso_exists and module_exists and (date_ok or time_ok))
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }