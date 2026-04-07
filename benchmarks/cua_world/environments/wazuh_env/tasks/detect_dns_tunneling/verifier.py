#!/usr/bin/env python3
"""
Verifier for Detect DNS Tunneling task.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_dns_tunneling(traj, env_info, task_info):
    """
    Verifies the DNS tunneling detection task by analyzing exported config and logtest results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_rule_id = str(metadata.get('required_rule_id', '100050'))
    
    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # Criterion 1: Log Ingestion Configuration (20 pts)
    # ================================================================
    ossec_conf = result.get('ossec_conf', '')
    # Check for <localfile> block with correct location
    # Robust regex to handle whitespace/XML variations
    log_config_regex = r"<localfile>[\s\S]*?<location>/var/log/custom_dns\.log</location>"
    
    if re.search(log_config_regex, ossec_conf):
        score += 20
        feedback_parts.append("Log ingestion configured correctly in ossec.conf")
    else:
        feedback_parts.append("Failed to find correct <localfile> configuration for /var/log/custom_dns.log")

    # ================================================================
    # Criterion 2: Decoder Functionality (Test via Logtest) (30 pts)
    # ================================================================
    # We check the logtest output for the malicious log line.
    # It should have extracted fields even if the rule didn't fire.
    
    logtest_mal = result.get('logtest_malicious', {})
    logtest_output = logtest_mal.get('output', {})
    
    # Check if a custom decoder fired
    decoder_name = logtest_mal.get('decoder', {}).get('name', '')
    
    # We expect 'custom-dns' or whatever they named it, but crucially, fields must be extracted.
    extracted_domain = logtest_mal.get('data', {}).get('domain', '')
    extracted_srcip = logtest_mal.get('data', {}).get('srcip', '')
    
    if extracted_domain:
        score += 15
        feedback_parts.append(f"Decoder successfully extracted domain: {extracted_domain}")
    else:
        feedback_parts.append("Decoder failed to extract 'domain' field")
        
    if extracted_srcip:
        score += 15
        feedback_parts.append(f"Decoder successfully extracted srcip: {extracted_srcip}")
    else:
        feedback_parts.append("Decoder failed to extract 'srcip' field")

    # ================================================================
    # Criterion 3: Rule Functionality (Test via Logtest) (40 pts)
    # ================================================================
    # The rule should trigger ID 100050 for the malicious log
    
    fired_rule_id = str(logtest_mal.get('rule', {}).get('id', ''))
    fired_rule_level = int(logtest_mal.get('rule', {}).get('level', 0))
    
    if fired_rule_id == required_rule_id:
        score += 30
        feedback_parts.append(f"Rule {required_rule_id} triggered successfully on malicious log")
        
        # Check rule level
        if fired_rule_level >= 12:
            score += 10
            feedback_parts.append(f"Rule level {fired_rule_level} meets requirement (>=12)")
        else:
            feedback_parts.append(f"Rule level {fired_rule_level} is too low (expected 12)")
    else:
        feedback_parts.append(f"Malicious log did not trigger rule {required_rule_id} (triggered: {fired_rule_id or 'None'})")

    # ================================================================
    # Criterion 4: False Positive Check (10 pts)
    # ================================================================
    # The benign log (google.com) should NOT trigger the alert
    
    logtest_ben = result.get('logtest_benign', {})
    benign_rule_id = str(logtest_ben.get('rule', {}).get('id', ''))
    
    if benign_rule_id != required_rule_id:
        score += 10
        feedback_parts.append("Benign log correctly did NOT trigger the alert")
    else:
        feedback_parts.append(f"Benign log triggered the alert (False Positive)")
        score -= 10 # Penalty for FP

    # ================================================================
    # Final Assessment
    # ================================================================
    
    # Must trigger the specific rule to pass
    passed = (fired_rule_id == required_rule_id) and (score >= 70)
    
    return {
        "passed": passed,
        "score": max(0, score), # No negative scores
        "feedback": " | ".join(feedback_parts)
    }