#!/usr/bin/env python3
"""
Verifier for future_deployment_time_simulation task.

Task:
  1. Add Austin, TX ground station (30.2672 N, 97.7431 W, 149m) and set as Default.
  2. Create 'Deployment_Sim' module with ISS (25544) and CSS (48274).
  3. Enable UTC time display.
  4. Open Time Controller, pause, and set time to April 15, 2026, at 14:30:00. (VLM verified)

Scoring (100 points, pass >= 70):
  - Austin QTH exists & coords correct: 15 pts
  - Austin set as Default QTH: 10 pts
  - Deployment_Sim module has both satellites: 20 pts
  - UTC time enabled: 15 pts
  - VLM: Time Controller open at end: 10 pts
  - VLM: Time Controller is paused/manual mode: 10 pts
  - VLM: Time Controller displays exactly 2026-04-15 14:30:00: 20 pts
"""

import json
import os
import re
import tempfile
import logging

# Standard framework imports for VLM verification
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

def _close_enough(value_str, expected_float, tolerance=0.1):
    """Check if string-encoded float is within tolerance of expected."""
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def _extract_vlm_json(text):
    """Safely extract JSON from VLM textual response."""
    match = re.search(r'\{.*\}', text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(0))
        except Exception:
            pass
    return {}

def verify_future_deployment_time_simulation(traj, env_info, task_info):
    """
    Verify the future deployment time simulation task using programmatic checks
    combined with VLM image verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    
    # --- Programmatic Verification ---
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/future_deployment_time_simulation_result.json", temp_path)
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

    # 1. Austin QTH (15 pts)
    if result.get('austin_exists'):
        lat_ok = _close_enough(result.get('austin_lat', ''), metadata.get('austin_lat', 30.2672), 0.1)
        lon_ok = _close_enough(result.get('austin_lon', ''), metadata.get('austin_lon', -97.7431), 0.1)
        alt_ok = _close_enough(result.get('austin_alt', ''), metadata.get('austin_alt', 149), 20)
        
        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("Austin QTH: correct")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append("Austin QTH: coordinates OK, altitude incorrect")
        else:
            score += 5
            feedback_parts.append("Austin QTH exists but coordinates inaccurate")
    else:
        feedback_parts.append("Austin QTH: NOT FOUND")

    # 2. Default QTH (10 pts)
    if result.get('default_qth_is_austin'):
        score += 10
        feedback_parts.append("Default QTH: Austin")
    else:
        feedback_parts.append("Default QTH: NOT set to Austin")

    # 3. Deployment_Sim module (20 pts)
    if result.get('module_exists'):
        has_iss = result.get('module_has_iss', False)
        has_css = result.get('module_has_css', False)
        if has_iss and has_css:
            score += 20
            feedback_parts.append("Deployment_Sim module: correct satellites (ISS, CSS)")
        elif has_iss or has_css:
            score += 10
            feedback_parts.append("Deployment_Sim module: partial satellites")
        else:
            feedback_parts.append("Deployment_Sim module: missing required satellites")
    else:
        feedback_parts.append("Deployment_Sim module: NOT FOUND")

    # 4. UTC Enabled (15 pts)
    if result.get('utc_enabled'):
        score += 15
        feedback_parts.append("UTC time: enabled")
    else:
        feedback_parts.append("UTC time: NOT enabled")


    # --- VLM Visual Verification ---
    vlm_feedback = []
    
    # Get trajectory frames and final screenshot
    frames = sample_trajectory_frames(traj, n=3)
    final_frame = get_final_screenshot(traj)
    images_to_check = frames + [final_frame] if final_frame else frames

    if not images_to_check:
        vlm_feedback.append("VLM Check: No screenshots available for time controller verification")
    else:
        vlm_prompt = """
        You are evaluating an AI agent's performance in a satellite tracking software interface (GPredict).
        The agent was instructed to open the floating 'Time Controller' dialog, pause the simulation, and adjust the time to exactly April 15, 2026, at 14:30:00. It must leave this dialog OPEN.
        
        Look at the sequence of screenshots, paying special attention to the FINAL screenshot.
        
        Please evaluate the following conditions and return ONLY a JSON object with boolean true/false values:
        1. "time_controller_open_at_end": In the final screenshot, is the 'Time Controller' dialog window clearly visible and open?
        2. "is_paused": In the final screenshot, is the Time Controller paused or in manual mode (e.g., the Stop/Pause button is active, or the Play button is NOT pressed)?
        3. "correct_date": In the final screenshot, does the Time Controller display the date April 15, 2026 (or 15/04/2026, 2026-04-15)?
        4. "correct_time": In the final screenshot, does the Time Controller display the exact time 14:30:00?
        
        Ensure your response is valid JSON. Example:
        {"time_controller_open_at_end": true, "is_paused": true, "correct_date": true, "correct_time": true}
        """

        try:
            vlm_response = query_vlm(images=images_to_check, prompt=vlm_prompt)
            
            # Extract text response from VLM output
            vlm_text = ""
            if isinstance(vlm_response, dict):
                vlm_text = vlm_response.get('response', '') or vlm_response.get('text', '')
            elif isinstance(vlm_response, str):
                vlm_text = vlm_response
                
            vlm_results = _extract_vlm_json(vlm_text)
            
            if not vlm_results:
                vlm_feedback.append("VLM Check: Could not parse response")
            else:
                # Score VLM components
                if vlm_results.get('time_controller_open_at_end', False):
                    score += 10
                    vlm_feedback.append("Time Controller: Open at end")
                else:
                    vlm_feedback.append("Time Controller: NOT open at end")

                if vlm_results.get('is_paused', False):
                    score += 10
                    vlm_feedback.append("Time Controller: Paused")
                else:
                    vlm_feedback.append("Time Controller: NOT paused")

                date_ok = vlm_results.get('correct_date', False)
                time_ok = vlm_results.get('correct_time', False)
                
                if date_ok and time_ok:
                    score += 20
                    vlm_feedback.append("Simulated Time: Exactly 2026-04-15 14:30:00")
                elif date_ok or time_ok:
                    score += 10
                    vlm_feedback.append("Simulated Time: Partially correct")
                else:
                    vlm_feedback.append("Simulated Time: Incorrect")
                    
        except Exception as e:
            vlm_feedback.append(f"VLM Check Failed: {e}")

    # Combine feedback
    feedback_parts.extend(vlm_feedback)
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }