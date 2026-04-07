#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_web_directory_enumeration(traj, env_info, task_info):
    """
    Verify the web directory enumeration task.
    
    Scoring Criteria (Total 100):
    - Nginx Installed: 10 pts
    - Log Configuration: 20 pts
    - Rule Existence: 10 pts
    - Rule Logic (Parent, Freq, Time, IP): 40 pts
    - Functional Detection (Attack works): 20 pts
    
    Pass Threshold: 70 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    feedback_parts = []
    
    # 1. Nginx Installation (10 pts)
    if result.get("nginx_installed", False):
        score += 10
        feedback_parts.append("Nginx installed")
    else:
        feedback_parts.append("Nginx NOT installed")

    # 2. Log Configuration (20 pts)
    if result.get("log_configured", False):
        score += 20
        feedback_parts.append("Logs configured")
    else:
        feedback_parts.append("ossec.conf missing Nginx log config")

    # 3. Rule Existence (10 pts)
    if result.get("rule_exists", False):
        score += 10
        feedback_parts.append("Rule 100500 created")
    else:
        feedback_parts.append("Rule 100500 missing")

    # 4. Rule Logic (40 pts total)
    logic_score = 0
    if result.get("rule_parent_correct", False): logic_score += 10
    if result.get("rule_frequency_correct", False): logic_score += 10
    if result.get("rule_timeframe_correct", False): logic_score += 10
    if result.get("rule_same_ip_correct", False): logic_score += 10
    
    if logic_score == 40:
        feedback_parts.append("Rule logic correct")
    elif logic_score > 0:
        feedback_parts.append(f"Rule logic partial ({logic_score}/40)")
    else:
        feedback_parts.append("Rule logic incorrect")
    
    score += logic_score

    # 5. Functional Detection (20 pts)
    if result.get("attack_detected", False):
        score += 20
        feedback_parts.append("Attack successfully detected")
    else:
        feedback_parts.append("Attack simulation failed to trigger alert")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }