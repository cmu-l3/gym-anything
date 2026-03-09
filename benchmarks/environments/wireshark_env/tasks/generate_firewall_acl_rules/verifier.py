#!/usr/bin/env python3
"""
Verifier for generate_firewall_acl_rules task.

Checks:
1. Cisco IOS rule file exists, was created during task, and contains correct IP/Syntax.
2. Iptables rule file exists, was created during task, and contains correct IP/Syntax.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_firewall_rules(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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

    # Basic Info
    ground_truth_ip = result.get('ground_truth_ip', '').strip()
    if not ground_truth_ip:
        return {"passed": False, "score": 0, "feedback": "System Error: Ground truth IP could not be determined."}

    score = 0
    feedback_parts = []
    
    # --- Check 1: Cisco Rule (50 points) ---
    cisco = result.get('cisco_file', {})
    c_exists = cisco.get('exists', False)
    c_fresh = cisco.get('created_during_task', False)
    c_content = cisco.get('content', '')

    if c_exists and c_fresh:
        score += 10
        # Check Syntax
        if "access-list" in c_content and "deny" in c_content:
            score += 20
            feedback_parts.append("Cisco syntax valid.")
        else:
            feedback_parts.append("Cisco syntax missing keywords (access-list, deny).")
        
        # Check IP
        if ground_truth_ip in c_content:
            score += 20
            feedback_parts.append(f"Cisco rule blocks correct IP ({ground_truth_ip}).")
        else:
            feedback_parts.append(f"Cisco rule does NOT contain correct IP {ground_truth_ip}.")
    elif c_exists:
        feedback_parts.append("Cisco file exists but was not created during this task session.")
    else:
        feedback_parts.append("Cisco rule file not found.")

    # --- Check 2: Iptables Rule (50 points) ---
    ipt = result.get('iptables_file', {})
    i_exists = ipt.get('exists', False)
    i_fresh = ipt.get('created_during_task', False)
    i_content = ipt.get('content', '')

    if i_exists and i_fresh:
        score += 10
        # Check Syntax
        if "iptables" in i_content and ("DROP" in i_content or "REJECT" in i_content):
            score += 20
            feedback_parts.append("Iptables syntax valid.")
        else:
            feedback_parts.append("Iptables syntax missing keywords (iptables, DROP/REJECT).")
            
        # Check IP
        if ground_truth_ip in i_content:
            score += 20
            feedback_parts.append(f"Iptables rule blocks correct IP ({ground_truth_ip}).")
        else:
            feedback_parts.append(f"Iptables rule does NOT contain correct IP {ground_truth_ip}.")
    elif i_exists:
        feedback_parts.append("Iptables file exists but was not created during this task session.")
    else:
        feedback_parts.append("Iptables rule file not found.")

    # Final logic
    passed = score >= 80  # Require good performance on both, or perfect on one + partial other
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }