#!/usr/bin/env python3
"""Verifier for functional_check_flight task.

This verifier uses a combination of programmed telemetry checks and VLM trajectory analysis.

Criteria:
1. STAT_FLTTIME > initial  (Proves vehicle was actually in the air) [20 pts]
2. STAT_RUNTIME > initial  (Proves vehicle was armed) [10 pts]
3. is_armed == False       (Proves vehicle landed/disarmed safely) [10 pts]
4. VLM Trajectory Check    (Visually confirms Takeoff, ~25m altitude, RTL/Land) [30 pts]
5. Report File Created     (Exists and modified during task) [10 pts]
6. Report Alt/GPS/Status   (Contains ~25m, GPS coords, and "PASS") [20 pts]
"""

import json
import os
import re
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying a drone simulation task in QGroundControl.
The user was instructed to:
1. Arm the vehicle and command a takeoff to 25 meters.
2. Observe the hover at ~25m.
3. Command a Return to Launch (RTL) or Land.

Look closely at this sequence of screenshots from the agent's session.
Pay attention to the Fly View HUD (center/right side), specifically:
- Did the altitude indicator (green numbers usually on the right) increase from 0 to around 25 m?
- Did the flight mode (top bar) transition (e.g., Takeoff -> Hold/Loiter -> RTL -> Land)?
- Does the final or near-final frame show the drone back on the ground (Altitude near 0)?

Please return a JSON response with your findings:
{
    "took_off_to_altitude": true/false,
    "reached_approx_25m": true/false,
    "initiated_return_or_land": true/false,
    "reasoning": "brief explanation of the sequence"
}
"""

def verify_functional_check_flight(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # Read exported result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Could not read export result: {e}'}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # 1. Telemetry Verification (MAVLink Stats)
    # ---------------------------------------------------------
    init_stats = result.get('initial_stats', {})
    final_stats = result.get('final_stats', {})
    
    init_flttime = float(init_stats.get('STAT_FLTTIME', 0))
    init_runtime = float(init_stats.get('STAT_RUNTIME', 0))
    
    final_flttime = float(final_stats.get('STAT_FLTTIME', 0))
    final_runtime = float(final_stats.get('STAT_RUNTIME', 0))
    is_armed = final_stats.get('is_armed', False)
    
    # Check flight time (Did it fly?)
    if final_flttime > init_flttime:
        score += 20
        feedback.append(f"STAT_FLTTIME increased ({init_flttime}->{final_flttime}s) - Vehicle flew (+20)")
    else:
        feedback.append("STAT_FLTTIME did not increase - Vehicle did not log flight time (+0)")

    # Check run time (Did it arm?)
    if final_runtime > init_runtime:
        score += 10
        feedback.append(f"STAT_RUNTIME increased ({init_runtime}->{final_runtime}s) - Vehicle armed (+10)")
    else:
        feedback.append("STAT_RUNTIME did not increase - Vehicle never armed (+0)")

    # Check disarmed state
    if not is_armed and final_runtime > init_runtime:
        score += 10
        feedback.append("Vehicle successfully disarmed at end of task (+10)")
    elif is_armed:
        feedback.append("Vehicle is still ARMED at end of task - unsafe state (+0)")

    # ---------------------------------------------------------
    # 2. Document Verification (Report)
    # ---------------------------------------------------------
    if result.get('report_found', False) and result.get('report_modified', False):
        score += 10
        feedback.append("Inspection report created and modified during task (+10)")
        
        report_text = result.get('report_content', '').replace('\\n', '\n')
        
        # Check Altitude (~25m)
        alt_match = re.search(r'(?:alt|altitude).*?(2[4-6](?:\.\d+)?)', report_text, re.IGNORECASE)
        if alt_match:
            score += 10
            feedback.append(f"Report includes valid altitude ({alt_match.group(1)}m) (+10)")
        else:
            feedback.append("Report missing valid altitude near 25m (+0)")
            
        # Check GPS/Status
        has_gps = bool(re.search(r'35\.\d+.*?149\.\d+|149\.\d+.*?35\.\d+', report_text))
        has_pass = "PASS" in report_text.upper()
        
        if has_gps and has_pass:
            score += 10
            feedback.append("Report includes GPS coordinates and PASS status (+10)")
        elif has_gps:
            score += 5
            feedback.append("Report includes GPS but missing PASS status (+5)")
        elif has_pass:
            score += 5
            feedback.append("Report includes PASS status but missing GPS (+5)")
        else:
            feedback.append("Report missing GPS coordinates and PASS status (+0)")
    else:
        feedback.append("Inspection report not found or not modified (+0/30)")

    # ---------------------------------------------------------
    # 3. VLM Trajectory Verification
    # ---------------------------------------------------------
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if final and final not in frames:
                frames.append(final)
                
            if frames:
                vlm_resp = query_vlm(images=frames, prompt=VLM_PROMPT)
                if vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    
                    if parsed.get("took_off_to_altitude"):
                        score += 10
                        feedback.append("VLM: Visual confirmed takeoff (+10)")
                    if parsed.get("reached_approx_25m"):
                        score += 10
                        feedback.append("VLM: Visual confirmed reached ~25m (+10)")
                    if parsed.get("initiated_return_or_land"):
                        score += 10
                        feedback.append("VLM: Visual confirmed RTL/Land sequence (+10)")
                        
                    feedback.append(f"VLM Notes: {parsed.get('reasoning', 'None')}")
                else:
                    feedback.append(f"VLM Query failed: {vlm_resp.get('error')} (+0/30)")
            else:
                feedback.append("No trajectory frames available for VLM verification (+0/30)")
        except Exception as e:
            feedback.append(f"VLM Error: {str(e)} (+0/30)")
    else:
        feedback.append("VLM capability not available in this environment (+0/30)")

    passed = score >= 70
    
    return {
        'passed': passed,
        'score': score,
        'feedback': " | ".join(feedback)
    }