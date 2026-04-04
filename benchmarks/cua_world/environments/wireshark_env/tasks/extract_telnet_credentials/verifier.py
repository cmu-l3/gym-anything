#!/usr/bin/env python3
"""
Verifier for extract_telnet_credentials task.

Checks:
1. Report file existence and freshness (Anti-gaming).
2. Credentials match ground truth (Accuracy).
3. Wireshark UI usage via VLM trajectory (Process).
"""

import json
import os
import sys
import tempfile
import logging
from vlm_utils import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_telnet_credentials(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # --- Check 1: File Existence & Anti-Gaming (20 pts) ---
    if result.get('file_exists'):
        if result.get('file_created_during_task'):
            score += 20
            feedback_parts.append("Report file created during task.")
        else:
            score += 10
            feedback_parts.append("Report file exists but timestamp is old.")
    else:
        feedback_parts.append("Report file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Check 2: Credentials Accuracy (60 pts) ---
    gt_user = result.get('gt_username', '')
    gt_pass = result.get('gt_password', '')
    
    user_val = result.get('extracted_username', '')
    pass_val = result.get('extracted_password', '')

    # Username (Case-insensitive)
    if user_val and gt_user and user_val.lower() == gt_user.lower():
        score += 30
        feedback_parts.append(f"Username correct ({user_val}).")
    else:
        feedback_parts.append(f"Username incorrect or missing (Got: '{user_val}', Expected: '{gt_user}').")

    # Password (Case-sensitive preferred, but lenient for this task usually)
    if pass_val and gt_pass and pass_val == gt_pass:
        score += 30
        feedback_parts.append("Password correct.")
    elif pass_val and gt_pass and pass_val.lower() == gt_pass.lower():
        score += 25 # Slight penalty for case mismatch if it matters, usually pass is case sensitive
        feedback_parts.append("Password correct (case mismatch).")
    else:
        feedback_parts.append(f"Password incorrect or missing (Got: '{pass_val}').")

    # --- Check 3: Process Verification (VLM) (20 pts) ---
    # We want to ensure they used Wireshark, not just strings/grep on the file.
    # While exact enforcement is hard, we look for Wireshark UI in trajectory.
    
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
         # Fallback to result.wireshark_running if no frames
        if result.get('wireshark_running'):
            score += 10
            feedback_parts.append("Wireshark was running.")
        else:
             feedback_parts.append("Wireshark usage not detected.")
    else:
        vlm_prompt = """
        Review these screenshots of a user performing a network forensics task.
        Question: Is the 'Wireshark' application visible and open in any of these frames? 
        Look for the characteristic shark fin icon, packet list (colored rows), or 'Follow TCP Stream' dialog.
        Respond with JSON: {"wireshark_visible": true/false}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get('success') and vlm_res['parsed'].get('wireshark_visible'):
                score += 20
                feedback_parts.append("Visual evidence of Wireshark usage confirmed.")
            elif result.get('wireshark_running'):
                score += 10
                feedback_parts.append("Wireshark process found, but UI not clearly identified in sample frames.")
            else:
                feedback_parts.append("No visual evidence of Wireshark usage.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            if result.get('wireshark_running'):
                score += 10 # Fallback points
                feedback_parts.append("Wireshark process running (VLM failed).")

    # Pass Threshold
    # Must get username AND password correct (20 + 30 + 30 = 80 min)
    passed = (score >= 70) and (gt_user.lower() == user_val.lower()) and (gt_pass == pass_val)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }