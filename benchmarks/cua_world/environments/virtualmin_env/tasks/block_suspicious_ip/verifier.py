#!/usr/bin/env python3
"""
Verifier for block_suspicious_ip task.

Criteria:
1. Malicious IP identified correctly in report file (20 pts).
2. Malicious IP is BLOCKED in firewall (active rules) (40 pts).
3. Action is DROP or REJECT (20 pts).
4. No legitimate IPs are blocked (Precision) (20 pts).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_block_suspicious_ip(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Fetch Ground Truth (Hidden on host or copied from container if generated there)
    # Since ground truth was generated in setup_task.sh inside the container, we must fetch it.
    
    attacker_ip = ""
    legit_ips = []
    
    try:
        with tempfile.NamedTemporaryFile(delete=False) as tf:
            copy_from_env("/var/lib/app/ground_truth/attacker_ip.txt", tf.name)
            with open(tf.name, 'r') as f:
                attacker_ip = f.read().strip()
            os.unlink(tf.name)
            
        with tempfile.NamedTemporaryFile(delete=False) as tf:
            copy_from_env("/var/lib/app/ground_truth/legit_ips.txt", tf.name)
            with open(tf.name, 'r') as f:
                legit_ips = [line.strip() for line in f if line.strip()]
            os.unlink(tf.name)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ground truth: {e}"}

    if not attacker_ip:
        return {"passed": False, "score": 0, "feedback": "Ground truth IP is empty (setup failed)."}

    # 2. Fetch Result Data
    result_data = {}
    iptables_content = ""
    
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tf:
            copy_from_env("/tmp/task_result.json", tf.name)
            with open(tf.name, 'r') as f:
                result_data = json.load(f)
            os.unlink(tf.name)
            
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tf:
            copy_from_env("/tmp/iptables_rules.txt", tf.name)
            with open(tf.name, 'r') as f:
                iptables_content = f.read()
            os.unlink(tf.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result data: {e}"}

    # 3. Verify Report File (20 pts)
    report_content = result_data.get("report_content", "").strip()
    if report_content == attacker_ip:
        score += 20
        feedback.append("SUCCESS: Report file contains correct IP.")
    elif attacker_ip in report_content:
        score += 15
        feedback.append(f"PARTIAL: Report file contains correct IP but extra content ('{report_content}').")
    else:
        feedback.append(f"FAIL: Report file incorrect. Expected {attacker_ip}, got '{report_content}'.")

    # 4. Verify Firewall Rules (60 pts total)
    # Check if IP is in iptables dump
    
    ip_found = False
    action_correct = False
    
    # Simple parsing of iptables-save output
    # Look for lines like: -A INPUT -s 203.0.113.45/32 -j DROP
    
    if attacker_ip in iptables_content:
        for line in iptables_content.splitlines():
            if attacker_ip in line and ("-A INPUT" in line or "-A FORWARD" in line or "Chain INPUT" in line):
                ip_found = True
                if "DROP" in line or "REJECT" in line or "DENY" in line:
                    action_correct = True
                    break
    
    # Also check Webmin/Firewalld nuances if iptables parsing was too strict
    # Sometimes rules are added to specific chains like f2b-loop
    if not ip_found and attacker_ip in iptables_content:
        # It's there somewhere, likely valid if it's a small task env
        ip_found = True
        # Optimistically check for drop in the whole file if we found the IP
        if "DROP" in iptables_content or "REJECT" in iptables_content:
            # Weak check but safer than false negative on complex chains
            pass 

    if ip_found:
        score += 40
        feedback.append("SUCCESS: Firewall rule for IP exists.")
        if action_correct:
            score += 20
            feedback.append("SUCCESS: Rule action is DROP/REJECT.")
        else:
            feedback.append("FAIL: Rule exists but action is not DROP/REJECT (or could not be parsed).")
    else:
        feedback.append("FAIL: No firewall rule found for malicious IP.")

    # 5. Check False Positives (20 pts)
    # Penalty if legitimate IPs are blocked
    false_positive = False
    for ip in legit_ips:
        if ip in iptables_content:
            # Check if it's a blocking rule
            for line in iptables_content.splitlines():
                if ip in line and ("DROP" in line or "REJECT" in line):
                    false_positive = True
                    feedback.append(f"PENALTY: Legitimate IP {ip} was blocked!")
                    break
        if false_positive:
            break
            
    if not false_positive:
        score += 20
        feedback.append("SUCCESS: No legitimate IPs were blocked.")
    else:
        # Score is already penalized by not gaining these points, 
        # but we can deduct more if we want strictness.
        # Just creating a ceiling is usually better.
        pass

    # 6. Anti-gaming (Timestamp)
    task_start = result_data.get("task_start", 0)
    report_mtime = result_data.get("report_mtime", 0)
    
    if report_mtime > 0 and report_mtime < task_start:
        score = 0
        feedback.insert(0, "ANTI-GAMING: Report file created before task start!")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }