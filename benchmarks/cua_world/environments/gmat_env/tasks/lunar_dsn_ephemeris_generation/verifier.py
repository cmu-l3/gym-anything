#!/usr/bin/env python3
"""
Verifier for lunar_dsn_ephemeris_generation@1

Evaluates whether the agent successfully generated CCSDS OEM and SPICE SPK
ephemeris files for a lunar orbit using the correct force model and step sizes.

Scoring (100 points total, Pass Threshold: 65)
1. OEM File Correctness (30 pts): Exists, has CCSDS headers, correct step size (60s).
2. OEM Duration (15 pts): ~7 days of data (~10081 points).
3. SPK File Correctness (15 pts): Exists, binary DAF format, size > 100KB.
4. Force Model config (20 pts): Script includes Luna (deg/order>=10), Earth, Sun, SRP.
5. VLM Trajectory (20 pts): Visual evidence the agent interacted with GMAT UI for ephemeris.
"""

import json
import os
import re
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """You are evaluating an AI agent's performance in NASA GMAT.
The agent's task was to configure a Lunar orbit and export ephemeris files (OEM and SPK).

Review the provided screenshots (which include trajectory frames and the final state) and determine:
1. Is there evidence the agent used the GMAT GUI to configure the mission? (e.g., configuring EphemerisFile, ForceModel, or Propagator dialogs)
2. Is there visual evidence of a successful propagation run? (e.g., ground track plots, 3D orbit views of the Moon, or message window showing "Mission run completed")

Return a JSON object:
{
    "gui_interaction_visible": true/false,
    "propagation_run_visible": true/false,
    "reasoning": "Brief explanation of what is visible in the frames"
}
"""


def verify_lunar_dsn_ephemeris(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_points = metadata.get('expected_oem_data_points', 10081)
    
    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # 1. Retrieve the exported JSON result
    # ---------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            results = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # ---------------------------------------------------------
    # 2. Evaluate OEM File (30 points step size/format + 15 points duration)
    # ---------------------------------------------------------
    oem_file = results.get('oem_file', {})
    oem_has_header = results.get('oem_has_header', False)
    oem_pts = int(results.get('oem_data_points', 0))
    t1_str = results.get('oem_first_time', '')
    t2_str = results.get('oem_second_time', '')
    
    if oem_file.get('exists') and oem_file.get('created_during_task'):
        if oem_has_header:
            score += 15
            feedback.append("OEM file successfully generated with valid CCSDS headers.")
            
            # Check step size (difference between first two time points)
            try:
                # Format is typically 2026-03-01T12:00:00.000
                fmt = "%Y-%m-%dT%H:%M:%S.%f"
                t1 = datetime.strptime(t1_str, fmt)
                t2 = datetime.strptime(t2_str, fmt)
                step_size = (t2 - t1).total_seconds()
                
                if abs(step_size - 60.0) < 1.0:
                    score += 15
                    feedback.append("OEM step size correctly verified as 60 seconds.")
                else:
                    feedback.append(f"OEM step size incorrect: {step_size}s (expected 60s).")
            except Exception as e:
                feedback.append(f"Could not parse OEM timestamps for step size verification: {e}")
        else:
            feedback.append("OEM file exists but lacks required CCSDS headers.")
            
        # Duration verification (15 points)
        # 7 days at 60s steps = 10080 intervals + 1 initial point = 10081
        if 9900 <= oem_pts <= 10200:
            score += 15
            feedback.append(f"OEM duration correct: {oem_pts} data points (7 days).")
        else:
            feedback.append(f"OEM duration incorrect: {oem_pts} points (expected ~{expected_points}).")
    else:
        feedback.append("OEM file was not generated during the task.")

    # ---------------------------------------------------------
    # 3. Evaluate SPK File (15 points)
    # ---------------------------------------------------------
    spk_file = results.get('spk_file', {})
    spk_binary = results.get('spk_is_binary', False)
    
    if spk_file.get('exists') and spk_file.get('created_during_task'):
        # A 7-day SPK at 60s should be several MBs. Check if > 100KB (102400 bytes)
        size_valid = spk_file.get('size', 0) > 102400
        if spk_binary and size_valid:
            score += 15
            feedback.append("SPK binary file successfully generated with expected data size.")
        else:
            score += 5
            feedback.append("SPK file exists but failed binary signature or size check.")
    else:
        feedback.append("SPK file was not generated during the task.")

    # ---------------------------------------------------------
    # 4. Evaluate Force Model in Script (20 points)
    # ---------------------------------------------------------
    temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
    script_content = ""
    try:
        copy_from_env("/tmp/lunar_dsn.script", temp_script.name)
        if os.path.getsize(temp_script.name) > 0:
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()
    except Exception:
        pass
    finally:
        if os.path.exists(temp_script.name):
            os.unlink(temp_script.name)

    if script_content:
        # Check Luna central body & gravity
        has_luna_body = bool(re.search(r'CentralBody\s*=\s*Luna', script_content))
        degree_match = re.search(r'GravityField\.Luna\.Degree\s*=\s*(\d+)', script_content)
        has_high_deg = False
        if degree_match and int(degree_match.group(1)) >= 10:
            has_high_deg = True

        # Check Point Masses (Earth and Sun)
        has_earth_sun = bool(re.search(r'PointMasses\s*=\s*\{[^}]*Earth[^}]*\}', script_content) and 
                             re.search(r'PointMasses\s*=\s*\{[^}]*Sun[^}]*\}', script_content))
                             
        # Check SRP
        has_srp = bool(re.search(r'SRP\s*=\s*On', script_content))
        
        fm_score = 0
        if has_luna_body and has_high_deg: fm_score += 10
        if has_earth_sun: fm_score += 5
        if has_srp: fm_score += 5
        
        score += fm_score
        feedback.append(f"Force Model logic score: {fm_score}/20.")
    else:
        feedback.append("Could not find or read the saved script for Force Model verification.")

    # ---------------------------------------------------------
    # 5. VLM Trajectory Verification (20 points)
    # ---------------------------------------------------------
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        if frames and final_frame:
            images = frames + [final_frame]
            vlm_resp = query_vlm(images=images, prompt=build_vlm_prompt())
            
            if vlm_resp and vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                gui_ok = parsed.get("gui_interaction_visible", False)
                run_ok = parsed.get("propagation_run_visible", False)
                
                vlm_score = 0
                if gui_ok: vlm_score += 10
                if run_ok: vlm_score += 10
                
                score += vlm_score
                feedback.append(f"VLM trajectory analysis (+{vlm_score}): {parsed.get('reasoning', '')}")
            else:
                feedback.append("VLM query failed or returned no valid JSON; skipping VLM points.")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        feedback.append("VLM verification skipped due to framework unavailability.")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }