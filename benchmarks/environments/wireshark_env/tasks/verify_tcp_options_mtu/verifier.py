#!/usr/bin/env python3
"""
Verifier for verify_tcp_options_mtu task.
Checks:
1. Report file existence and creation time.
2. Accuracy of extracted TCP values (MSS, WScale).
3. Accuracy of Max Payload and TSO detection logic.
"""

import json
import tempfile
import os
import re

def verify_tcp_options(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize scoring
    score = 0
    feedback = []
    
    # 1. Check Report Existence (10 pts)
    if result.get('report_exists', False):
        score += 5
        if result.get('report_created_during_task', False):
            score += 5
            feedback.append("Report file created during task.")
        else:
            feedback.append("Report file exists but timestamp is old.")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not found at expected path."}

    # Parse User Content
    user_raw = result.get('user_content_raw', '')
    user_data = {}
    
    # Regex to parse "Key: Value" lines case-insensitive
    for line in user_raw.splitlines():
        if ':' in line:
            key, val = line.split(':', 1)
            user_data[key.strip().lower()] = val.strip()

    gt = result.get('ground_truth', {})

    # Helper function to check integer values
    def check_int(key_name, gt_key, points, tolerance=0):
        user_val_str = user_data.get(key_name.lower())
        gt_val_str = gt.get(gt_key)
        
        if not user_val_str or not gt_val_str:
            feedback.append(f"Missing value for {key_name}")
            return 0
            
        try:
            u_val = int(re.sub(r'[^0-9]', '', user_val_str)) # Remove non-digits
            g_val = int(gt_val_str)
            if abs(u_val - g_val) <= tolerance:
                feedback.append(f"Correct {key_name}: {u_val}")
                return points
            else:
                feedback.append(f"Incorrect {key_name}: expected {g_val}, got {u_val}")
                return 0
        except ValueError:
            feedback.append(f"Invalid format for {key_name}: {user_val_str}")
            return 0

    # 2. Check MSS Values (30 pts)
    score += check_int("Client_MSS", "client_mss", 15)
    score += check_int("Server_MSS", "server_mss", 15)

    # 3. Check Window Scale Values (30 pts)
    score += check_int("Client_WScale", "client_wscale", 15)
    score += check_int("Server_WScale", "server_wscale", 15)

    # 4. Check Max Payload (15 pts)
    score += check_int("Max_Payload_Size", "max_payload", 15)

    # 5. Check TSO Detection (15 pts)
    user_tso = user_data.get("tso_detected", "").upper()
    gt_tso = gt.get("tso_detected", "NO")
    
    # Normalize user input (accept yes/no, true/false)
    if "YES" in user_tso or "TRUE" in user_tso:
        user_bool = "YES"
    else:
        user_bool = "NO"

    if user_bool == gt_tso:
        score += 15
        feedback.append(f"Correct TSO detection: {user_bool}")
    else:
        feedback.append(f"Incorrect TSO detection: expected {gt_tso}, got {user_bool}")

    return {
        "passed": score >= 85,
        "score": score,
        "feedback": " | ".join(feedback)
    }