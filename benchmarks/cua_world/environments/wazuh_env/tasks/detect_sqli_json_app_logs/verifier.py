#!/usr/bin/env python3
"""
Verifier for Detect SQLi Task.
Verifies:
1. Wazuh ingestion config (ossec.conf)
2. Detection rule existence and logic (local_rules.xml)
3. Successful alert generation (alerts.json)
"""

import json
import os
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_sqli(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    metadata = task_info.get('metadata', {})
    expected_rule_id = str(metadata.get('rule_id', '100100'))
    expected_log_path = metadata.get('log_file_path', '/var/log/custom_webapp/app.json')
    
    # 1. Verify Ingestion Configuration (20 pts)
    ossec_conf = result.get('ossec_conf_content', '')
    # Look for <localfile> block with correct path and format
    # Simple regex check
    # Note: XML parsing would be better but simple string check is robust enough for config existence
    has_localfile = False
    if f"<location>{expected_log_path}</location>" in ossec_conf:
        if "<log_format>json</log_format>" in ossec_conf:
            # Ideally checking if they are in the same block, but loose check is okay for partial scoring
            has_localfile = True
    
    # Stronger regex check for same block
    localfile_pattern = re.compile(r"<localfile>.*?<location>" + re.escape(expected_log_path) + r"</location>.*?<log_format>json</log_format>.*?</localfile>", re.DOTALL)
    if localfile_pattern.search(ossec_conf):
        score += 20
        feedback.append("Log ingestion configured correctly.")
    elif has_localfile:
        score += 10
        feedback.append("Log ingestion configured but check formatting (location/format).")
    else:
        feedback.append("Log ingestion configuration not found in ossec.conf.")

    # 2. Verify Rule Creation (20 pts)
    local_rules = result.get('local_rules_content', '')
    rule_exists = f'id="{expected_rule_id}"' in local_rules
    
    if rule_exists:
        score += 20
        feedback.append(f"Rule ID {expected_rule_id} created.")
    else:
        feedback.append(f"Rule ID {expected_rule_id} not found in local_rules.xml.")

    # 3. Verify Rule Logic (20 pts)
    # Check for SQLi patterns in the rule
    sqli_keywords = ["UNION", "SELECT", "OR", "1=1"]
    logic_score = 0
    if rule_exists:
        # Check level
        if 'level="12"' in local_rules or 'level="13"' in local_rules or 'level="14"' in local_rules:
            logic_score += 5
        
        # Check field targeting (http_query) or full log
        if "http_query" in local_rules:
            logic_score += 5
            
        # Check regex/match
        if any(k in local_rules for k in sqli_keywords):
            logic_score += 10
            
    score += logic_score
    if logic_score > 0:
        feedback.append("Rule logic checks passed.")

    # 4. Verify Alert Triggered (40 pts)
    alert_found = result.get('alert_found', False)
    alert_data = result.get('alert_data', {})
    
    if alert_found:
        # Validate alert details
        rule_data = alert_data.get('rule', {})
        if str(rule_data.get('id')) == expected_rule_id:
            score += 40
            feedback.append("SQL Injection alert triggered successfully.")
        else:
            score += 20
            feedback.append("Alert triggered but Rule ID mismatch (partial credit).")
    else:
        feedback.append("No alert triggered for the SQL Injection attempt.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }