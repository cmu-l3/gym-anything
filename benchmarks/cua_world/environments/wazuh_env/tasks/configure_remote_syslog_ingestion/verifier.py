#!/usr/bin/env python3
"""
Verifier for configure_remote_syslog_ingestion task.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_remote_syslog_ingestion(traj, env_info, task_info):
    """
    Verify Wazuh syslog configuration and custom rule.
    """
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
    feedback_parts = []
    
    # 1. Check if port is listening (20 pts)
    is_listening = result.get("is_listening_514", False)
    if is_listening:
        score += 20
        feedback_parts.append("Port 514/udp is open")
    else:
        feedback_parts.append("Port 514/udp NOT listening")

    # 2. Check ossec.conf configuration (40 pts)
    # Looking for <remote> block with syslog, udp, 514, and allowed-ips
    ossec_conf = result.get("ossec_conf_content", "")
    
    # Normalize whitespace for regex
    ossec_conf_clean = re.sub(r'\s+', ' ', ossec_conf)
    
    # Regex to find the specific remote block
    # Matches <remote> ... <connection>syslog</connection> ... </remote>
    # Note: Tags can be in any order inside <remote>
    has_remote_block = False
    has_syslog = False
    has_port = False
    has_udp = False
    has_allowed_ips = False
    
    # Simple check: Does it contain a remote block with these elements?
    # We look for the structure roughly.
    
    if "<remote>" in ossec_conf:
        # Extract remote blocks
        remote_blocks = re.findall(r'<remote>(.*?)</remote>', ossec_conf_clean, re.DOTALL)
        for block in remote_blocks:
            if "syslog" in block:
                has_syslog = True
                if "514" in block:
                    has_port = True
                if "udp" in block:
                    has_udp = True
                if "allowed-ips" in block and "172.16" in block:
                    has_allowed_ips = True
                
                # Check strict allowed-ips format if possible, but basic check is okay
                if has_syslog and has_port:
                    has_remote_block = True
                    break
    
    if has_remote_block:
        score += 30
        feedback_parts.append("Syslog remote config found")
        if has_allowed_ips:
            score += 10
            feedback_parts.append("Allowed IPs configured")
        else:
            feedback_parts.append("Missing or incorrect allowed-ips restriction")
    else:
        feedback_parts.append("Valid syslog remote configuration not found in ossec.conf")

    # 3. Check Custom Rule (20 pts)
    rules_content = result.get("local_rules_content", "")
    rule_id_found = "100100" in rules_content
    string_match_found = "%ASA-4-106023" in rules_content
    
    if rule_id_found and string_match_found:
        score += 20
        feedback_parts.append("Custom rule 100100 created correctly")
    elif rule_id_found:
        score += 10
        feedback_parts.append("Rule 100100 found but missing match string")
    else:
        feedback_parts.append("Custom rule 100100 not found")

    # 4. Functional Test (20 pts)
    alert_generated = result.get("alert_generated", False)
    if alert_generated:
        score += 20
        feedback_parts.append("Functional test passed: Alert generated")
    else:
        feedback_parts.append("Functional test failed: No alert generated")

    passed = score >= 70 and is_listening and alert_generated
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }