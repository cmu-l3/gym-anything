#!/usr/bin/env python3
"""
Verifier for export_v2x_mobility_traces task.

Multi-Criteria Verification:
1. FCD File creation & size verification (15 points)
2. NS2 Mobility File creation & size verification (25 points)
3. NS2 Activity File creation & size verification (15 points)
4. Application of trace limits (t=600s) verified internally (20 points)
5. Accurate line count summary created manually/via command line (15 points)
6. Trajectory verification via VLM showing CLI usage (10 points)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_v2x_mobility_traces(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read exported result json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    fcd_info = result.get('fcd_file', {})
    mob_info = result.get('mobility_file', {})
    act_info = result.get('activity_file', {})
    sum_info = result.get('summary_file', {})
    max_time_str = result.get('max_time_found', "-1")
    
    try:
        max_time = float(max_time_str)
    except ValueError:
        max_time = -1.0

    # Criterion 1: FCD Output (15 points)
    if fcd_info.get('exists') and fcd_info.get('created_during_task'):
        if fcd_info.get('size', 0) > 1000:
            score += 15
            feedback_parts.append("FCD file properly generated")
        else:
            feedback_parts.append("FCD file is suspiciously small")
    else:
        feedback_parts.append("FCD file missing or not generated during task")
        
    # Criterion 2: NS2 Mobility Trace (25 points)
    if mob_info.get('exists') and mob_info.get('created_during_task'):
        if mob_info.get('size', 0) > 500:
            score += 25
            feedback_parts.append("NS2 Mobility generated")
        else:
            feedback_parts.append("NS2 Mobility file too small")
    else:
        feedback_parts.append("NS2 Mobility file missing")
        
    # Criterion 3: NS2 Activity Trace (15 points)
    if act_info.get('exists') and act_info.get('created_during_task'):
        if act_info.get('size', 0) > 50:
            score += 15
            feedback_parts.append("NS2 Activity generated")
        else:
            feedback_parts.append("NS2 Activity file too small")
    else:
        feedback_parts.append("NS2 Activity file missing")
        
    # Criterion 4: Time Bounds Check (20 points)
    if mob_info.get('exists') and 0 < max_time <= 600.5:
        score += 20
        feedback_parts.append(f"Time boundary respected (Max time: {max_time}s)")
    elif max_time > 600.5:
        feedback_parts.append(f"Trace exceeds time limit (Max time: {max_time}s)")
    elif max_time <= 0 and mob_info.get('exists'):
        feedback_parts.append("Time boundary invalid/unreadable")
        
    # Criterion 5: Accurate line count summary (15 points)
    if sum_info.get('exists') and sum_info.get('created_during_task'):
        temp_mob = tempfile.NamedTemporaryFile(delete=False, suffix='.tcl')
        temp_sum = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/home/ga/SUMO_Output/ns2_mobility.tcl", temp_mob.name)
            copy_from_env("/home/ga/SUMO_Output/trace_summary.txt", temp_sum.name)
            
            with open(temp_mob.name, 'r') as f:
                actual_lines = sum(1 for line in f)
                
            with open(temp_sum.name, 'r') as f:
                sum_content = f.read().strip()
                
            match = re.search(r"total_mobility_lines=(\d+)", sum_content)
            if match:
                reported_lines = int(match.group(1))
                if abs(actual_lines - reported_lines) <= 5: # Small tolerance for trailing newlines
                    score += 15
                    feedback_parts.append(f"Line count correct ({reported_lines})")
                else:
                    feedback_parts.append(f"Line count inaccurate (Reported: {reported_lines}, Actual: {actual_lines})")
            else:
                feedback_parts.append("Summary report format incorrect")
        except Exception as e:
            feedback_parts.append(f"Could not verify summary: {e}")
        finally:
            if os.path.exists(temp_mob.name): os.unlink(temp_mob.name)
            if os.path.exists(temp_sum.name): os.unlink(temp_sum.name)
    else:
        feedback_parts.append("Summary file missing")

    # Criterion 6: Trajectory Verification via VLM (10 points)
    vlm_points = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            if frames and final:
                prompt = "Look at these frames from a Linux desktop. The agent is supposed to use a terminal window to run 'sumo' and 'traceExporter.py' commands. Do you see evidence of a terminal window being used to execute commands?\nRespond ONLY with a valid JSON object: {\"terminal_used\": true/false}"
                vlm_result = query_vlm(images=frames + [final], prompt=prompt)
                parsed = vlm_result.get("parsed", {})
                if parsed.get("terminal_used", False):
                    vlm_points = 10
                    feedback_parts.append("VLM verified CLI usage")
                else:
                    feedback_parts.append("VLM did not detect CLI usage")
            else:
                feedback_parts.append("Could not retrieve frames for VLM check")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append(f"VLM verification error: {e}")
    else:
        # Automatically grant VLM points if VLM is unavailable, provided everything else passes perfectly
        if score >= 90:
            vlm_points = 10
            
    score += vlm_points

    # Critical requirement calculation: The mobility file must exist and the time bound must be correctly processed
    critical_criteria_met = mob_info.get('exists') and 0 < max_time <= 600.5
    passed = score >= 70 and critical_criteria_met
    
    if not critical_criteria_met:
        feedback_parts.append("CRITICAL FAILURE: NS2 mobility missing or time limit ignored")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }