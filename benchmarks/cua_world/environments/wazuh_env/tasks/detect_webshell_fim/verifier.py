#!/usr/bin/env python3
"""
Verifier for detect_webshell_fim task.

Verifies:
1. ossec.conf: /var/www/html is monitored with realtime=yes
2. local_rules.xml: Rule 100050 exists, child of 554, level 12, matches .php
3. Alerts: Rule 100050 fired for the verification file (functional test)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_webshell_fim(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    verifier_file = metadata.get('verifier_file', 'verification_trigger.php')

    # Retrieve result file
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

    score = 0
    feedback = []

    # 1. Verify Manager Status (10 pts)
    if result.get('manager_running', False):
        score += 10
        feedback.append("Wazuh manager is running.")
    else:
        feedback.append("Wazuh manager is NOT running.")

    # 2. Verify ossec.conf (30 pts)
    ossec_conf = result.get('ossec_conf', '')
    
    # Check for <directories ... /var/www/html ...>
    # Logic: Look for the path inside a directories tag
    # Simplified regex check
    dir_match = re.search(r'<directories[^>]*>.*(/var/www/html).*</directories>', ossec_conf, re.DOTALL)
    
    if dir_match:
        dir_block = dir_match.group(0)
        # Check attributes
        if 'realtime="yes"' in dir_block:
            score += 15
            feedback.append("Real-time monitoring enabled for /var/www/html.")
        else:
            feedback.append("Monitoring enabled, but 'realtime' attribute missing or not 'yes'.")
            
        if 'report_changes="yes"' in dir_block:
            score += 15
            feedback.append("Report changes enabled.")
        else:
            feedback.append("'report_changes' attribute missing (minor, but requested).")
            # Partial credit if they missed report_changes but got realtime
            if 'realtime="yes"' in dir_block:
                 score += 5 
    else:
        feedback.append("Directory /var/www/html is NOT configured for FIM in ossec.conf.")

    # 3. Verify local_rules.xml (40 pts)
    local_rules = result.get('local_rules', '')
    
    # Check Rule ID 100050
    rule_match = re.search(r'<rule[^>]+id="100050"[^>]*>(.*?)</rule>', local_rules, re.DOTALL)
    
    if rule_match:
        rule_content = rule_match.group(1)
        rule_tag = rule_match.group(0)
        
        # Level check
        if 'level="12"' in rule_tag:
            score += 10
            feedback.append("Rule 100050 level is correct (12).")
        else:
            feedback.append("Rule 100050 level is incorrect.")

        # Parent ID check (if_sid 554)
        if '<if_sid>554</if_sid>' in rule_content:
            score += 10
            feedback.append("Rule parent (554) is correct.")
        else:
            feedback.append("Rule parent is not 554 (File added).")

        # Regex/Match check (.php)
        # Accept either <match> or <regex> or <field name="file">
        if re.search(r'\.php', rule_content):
            score += 20
            feedback.append("Rule correctly matches .php files.")
        else:
            feedback.append("Rule does not appear to contain a pattern for .php files.")
    else:
        feedback.append("Rule 100050 not found in local_rules.xml.")

    # 4. Verify Alert Trigger (20 pts)
    alerts_json_str = result.get('alerts_json', '')
    
    # Parse the grep output (which might be multiple JSON lines)
    triggered = False
    triggered_file = False
    
    for line in alerts_json_str.strip().split('\n'):
        if not line: continue
        try:
            alert = json.loads(line)
            rule = alert.get('rule', {})
            if str(rule.get('id')) == '100050':
                triggered = True
                # Check if it was for our verifier file or the user's test file
                syscheck = alert.get('syscheck', {})
                path = syscheck.get('path', '')
                if verifier_file in path:
                    triggered_file = True
                elif 'backdoor.php' in path:
                    triggered_file = True # User tested it themselves
        except:
            pass

    if triggered and triggered_file:
        score += 20
        feedback.append("Functional test PASSED: Alert 100050 triggered on PHP file creation.")
    elif triggered:
        score += 10
        feedback.append("Alert 100050 triggered, but not specifically for the test file (check logic).")
    else:
        feedback.append("Functional test FAILED: No alert generated for file creation. Check configuration and restart.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }