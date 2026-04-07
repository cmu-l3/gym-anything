#!/usr/bin/env python3
"""
Verifier for Detect Password Spraying Task.

Scoring Breakdown:
- Runtime Success (Alert Fired): 40 pts
- Log Ingestion Config: 15 pts
- Decoder Logic: 15 pts
- Rule Logic (XML structure): 30 pts

Total: 100 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_app_password_spraying(traj, env_info, task_info):
    """
    Verify the password spraying detection pipeline.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    config = result.get('config', {})
    runtime = result.get('runtime', {})
    
    score = 0
    feedback = []

    # 1. Runtime Success (The Gold Standard)
    # If the alert actually fired, they must have done everything right.
    if runtime.get('alert_fired', False):
        score += 40
        feedback.append("SUCCESS: Password spraying alert (Rule 100502) triggered during simulation.")
    else:
        feedback.append("FAIL: No alert generated during simulation.")
        if not runtime.get('manager_running', False):
            feedback.append("CRITICAL: Wazuh manager is not running.")

    # 2. Log Ingestion Config (15 pts)
    if config.get('log_ingestion', False):
        score += 15
        feedback.append("Config: Log file ingestion configured.")
    else:
        feedback.append("Config: Missing <localfile> block for /var/log/megacorp.log.")

    # 3. Decoder Logic (15 pts)
    decoder_pts = 0
    if config.get('decoder_srcip', False): decoder_pts += 7.5
    if config.get('decoder_user', False): decoder_pts += 7.5
    score += decoder_pts
    if decoder_pts == 15:
        feedback.append("Decoder: Fields (srcip, dstuser) correctly defined.")
    elif decoder_pts > 0:
        feedback.append("Decoder: Partially correct (missing some fields).")
    else:
        feedback.append("Decoder: No custom decoder found for srcip/dstuser.")

    # 4. Rule Logic (30 pts)
    # Even if runtime failed, give credit for correct XML logic
    rule_pts = 0
    if config.get('base_rule', False): rule_pts += 5
    if config.get('spray_rule', False): rule_pts += 5
    
    # Advanced logic check
    logic_pts = 0
    if config.get('logic_frequency', False): logic_pts += 5
    if config.get('logic_same_ip', False): logic_pts += 10
    if config.get('logic_diff_user', False): logic_pts += 5
    
    rule_pts += logic_pts
    score += rule_pts
    
    if logic_pts == 20:
        feedback.append("Rules: Logic matches requirements (frequency, same_ip, diff_user).")
    else:
        feedback.append("Rules: Logic incomplete (missing frequency, same_source_ip, or different_dstuser).")

    # Final check
    passed = score >= 60 and runtime.get('alert_fired', False)
    
    # If they got the alert to fire, they should pass regardless of regex parsing quirks
    # (The runtime check is strict, but config checks are backup)
    if runtime.get('alert_fired', False) and score < 70:
        score = 100 # Boost to 100 if it actually works, overriding static analysis misses
        passed = True

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }