#!/usr/bin/env python3
"""
Verifier for Investigate and Block Spam Traffic task.

Scores based on:
1. Blocked IP (30pts)
2. Blocked User Agent (30pts)
3. Blocked Referrer (30pts)
4. Did NOT block legitimate traffic (10pts)
"""

import json
import logging
import os
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_investigate_and_block_spam_traffic(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    spam_ip = metadata.get('spam_ip', '192.0.2.105')
    spam_ua = metadata.get('spam_ua', 'TrafficBotPro/3.0')
    spam_ref = metadata.get('spam_referrer', 'http://traffic-bot-pro.test/free-traffic')
    
    # Retrieve result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check database state
    blocked_ips = result.get('ips', '')
    blocked_refs = result.get('refs', '')
    blocked_uas = result.get('uas', '')
    
    score = 0
    feedback = []
    
    # 1. IP Check
    # Matomo allows comma or newline separation usually, or wildcard. 
    # We look for the exact string or contained string.
    if spam_ip in blocked_ips:
        score += 30
        feedback.append("Spam IP blocked correctly.")
    else:
        feedback.append(f"Spam IP {spam_ip} NOT found in exclusion list.")

    # 2. Referrer Check
    # User might block the whole domain or specific URL.
    # We accept if the key part "traffic-bot-pro.test" is blocked
    if "traffic-bot-pro.test" in blocked_refs:
        score += 30
        feedback.append("Spam Referrer blocked correctly.")
    else:
        feedback.append("Spam Referrer NOT found in exclusion list.")

    # 3. User Agent Check
    if "TrafficBotPro" in blocked_uas:
        score += 30
        feedback.append("Spam User Agent blocked correctly.")
    else:
        feedback.append("Spam User Agent NOT found in exclusion list.")

    # 4. Safety Check (False Positives)
    # Shouldn't block localhost or google
    safe_penalty = 0
    if "127.0.0.1" in blocked_ips or "::1" in blocked_ips:
        safe_penalty += 1
        feedback.append("WARNING: Blocked localhost IP!")
    
    if "google" in blocked_refs:
        safe_penalty += 1
        feedback.append("WARNING: Blocked Google!")

    if safe_penalty == 0:
        score += 10
        feedback.append("Safe traffic preserved.")
    else:
        score = max(0, score - (safe_penalty * 10)) # Deduct points

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "ips_found": blocked_ips,
            "refs_found": blocked_refs,
            "uas_found": blocked_uas
        }
    }