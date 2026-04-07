#!/usr/bin/env python3
"""
Verifier for detect_world_writable_file_fim@1 task.

Criteria:
1. Wazuh Manager is running (10 pts)
2. FIM (syscheck) is configured for /opt/secure_configs (30 pts)
3. Custom Rule 110001 exists in local_rules.xml with correct logic (30 pts)
4. Functional Test: Simulated chmod 777 triggered the alert (30 pts)
"""

import json
import os
import tempfile
import base64
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_world_writable_file_fim(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # 1. Check App Running (10 pts)
    if result.get('app_running', False):
        score += 10
        feedback_parts.append("Wazuh manager is running.")
    else:
        feedback_parts.append("Wazuh manager is NOT running.")

    # Decode configs
    try:
        ossec_conf = base64.b64decode(result.get('ossec_conf_b64', '')).decode('utf-8', errors='ignore')
        rules_xml = base64.b64decode(result.get('local_rules_b64', '')).decode('utf-8', errors='ignore')
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to decode configs: {e}"}

    # 2. Verify FIM Configuration (30 pts)
    # Looking for <directories ...>/opt/secure_configs</directories>
    # Must have check_all="yes" OR (perm="yes" and others)
    fim_regex = r'<directories[^>]*\/opt\/secure_configs<\/directories>'
    if re.search(fim_regex, ossec_conf):
        score += 30
        feedback_parts.append("FIM configured for /opt/secure_configs.")
        
        # Bonus check: is it realtime? (Not strictly required for points if it works, but good practice)
        if 'realtime="yes"' in re.search(r'<directories[^>]*>.*?\/opt\/secure_configs', ossec_conf, re.DOTALL).group(0):
            feedback_parts.append("(Realtime monitoring enabled).")
    else:
        feedback_parts.append("FIM NOT configured for /opt/secure_configs.")

    # 3. Verify Rule Configuration (30 pts)
    # Check for rule 110001
    rule_block = re.search(r'<rule id="110001".*?<\/rule>', rules_xml, re.DOTALL)
    if rule_block:
        rule_content = rule_block.group(0)
        rule_points = 0
        
        # Check level
        if 'level="12"' in rule_content:
            rule_points += 5
        
        # Check regex/match for permissions
        # Looking for w.$ or similar logic
        if re.search(r'w\.\$|<match>.*?w\..*?<\/match>', rule_content) or \
           re.search(r'syscheck\.perm_after', rule_content):
            rule_points += 25
            feedback_parts.append("Rule 110001 logic found.")
        else:
            feedback_parts.append("Rule 110001 exists but missing permission regex.")
            
        score += rule_points
    else:
        feedback_parts.append("Rule 110001 NOT found in local_rules.xml.")

    # 4. Functional Test (30 pts)
    # Did the export script successfully trigger the alert?
    if result.get('alert_triggered', False):
        score += 30
        feedback_parts.append("SUCCESS: Simulated 'chmod 777' triggered Rule 110001.")
        
        # Verification of alert detail
        detail = result.get('alert_detail', {})
        if detail.get('rule', {}).get('level') == 12:
            feedback_parts.append("Alert level correct.")
    else:
        feedback_parts.append("FAILURE: Simulated 'chmod 777' did NOT trigger the alert. (Did you restart the manager? Is realtime FIM active?)")

    passed = score >= 80  # Requires most components to be correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }