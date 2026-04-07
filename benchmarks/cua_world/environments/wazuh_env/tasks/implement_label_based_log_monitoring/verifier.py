#!/usr/bin/env python3
"""
Verifier for Implement Label-Based Log Monitoring Task.
"""

import json
import base64
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_label_based_log_monitoring(traj, env_info, task_info):
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
    
    # --- Decode Config Files ---
    try:
        ossec_conf = base64.b64decode(result.get('ossec_conf_b64', '')).decode('utf-8')
        local_rules = base64.b64decode(result.get('local_rules_b64', '')).decode('utf-8')
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": "Failed to decode configuration files"}

    # --- Criterion 1: Agent Label Configuration (20 pts) ---
    # Look for <label key="compliance">pci_dss</label>
    # Flexible regex for XML attributes
    label_pattern = r'<label\s+key=["\']compliance["\']\s*>pci_dss</label>'
    if re.search(label_pattern, ossec_conf):
        score += 20
        feedback.append("Agent label 'compliance:pci_dss' configured correctly.")
    else:
        feedback.append("Agent label configuration missing or incorrect in ossec.conf.")

    # --- Criterion 2: Log Collection Configuration (20 pts) ---
    # Look for <localfile> block with /var/log/payment_app.log
    # We check if the file path exists within a localfile block
    if "/var/log/payment_app.log" in ossec_conf and "<localfile>" in ossec_conf:
        # stricter check could involve parsing XML, but simple string check is robust enough for this context
        # assuming the user didn't write a comment with the path
        if re.search(r'<location>/var/log/payment_app.log</location>', ossec_conf):
            score += 20
            feedback.append("Log file monitoring configured correctly.")
        else:
            score += 10 # Partial credit if path is there but maybe tags wrong
            feedback.append("Log file path found, but XML structure looks incorrect.")
    else:
        feedback.append("Log monitoring for payment_app.log not found.")

    # --- Criterion 3: Rule Existence and Basics (30 pts) ---
    # Check for rule ID 100250 and level 12
    rule_basics = False
    if 'id="100250"' in local_rules or "id='100250'" in local_rules:
        if 'level="12"' in local_rules or "level='12'" in local_rules:
            if "Transaction: VOID" in local_rules:
                score += 30
                rule_basics = True
                feedback.append("Rule 100250 created with correct level and match.")
            else:
                score += 15
                feedback.append("Rule 100250 found, but missing correct match string.")
        else:
            score += 10
            feedback.append("Rule 100250 found, but incorrect alert level.")
    else:
        feedback.append("Rule 100250 not found in local_rules.xml.")

    # --- Criterion 4: Conditional Label Logic (10 pts) ---
    # This is the "Anti-Gaming" check. The rule MUST check the label.
    # Pattern: <field name="agent.labels.compliance">pci_dss</field>
    # OR dynamic field access
    label_logic_pattern = r'agent\.labels\.compliance'
    if rule_basics and re.search(label_logic_pattern, local_rules):
        score += 10
        feedback.append("Rule correctly uses label conditional logic.")
    elif rule_basics:
        feedback.append("Rule 100250 exists but DOES NOT check the agent label (Logic error).")

    # --- Criterion 5: Functional Verification (20 pts) ---
    # Did the alert actually trigger?
    alert_triggered = result.get('alert_triggered', False)
    if alert_triggered:
        score += 20
        feedback.append("Functional test PASSED: Alert triggered on log injection.")
        
        # Extra verification of alert content if available
        alert_data = result.get('alert_data', {})
        if isinstance(alert_data, dict) and str(alert_data.get('rule', {}).get('id')) == "100250":
            pass # ID matches, good
    else:
        feedback.append("Functional test FAILED: No alert generated. Check manager restart or rule syntax.")

    # Pass Threshold
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }