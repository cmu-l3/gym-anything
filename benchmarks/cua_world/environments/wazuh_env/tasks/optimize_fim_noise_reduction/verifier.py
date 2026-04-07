#!/usr/bin/env python3
"""
Verifier for Optimize FIM Noise Reduction task.

Checks:
1. ossec.conf configuration (realtime enabled, ignore sregex added)
2. Evidence of test files created by agent
3. Alert logic: Positive alert exists, Negative alert does NOT exist
"""

import json
import os
import re
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_fim_noise_reduction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
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
    
    # Data from result
    config_content = result.get('ossec_conf', '')
    alerts = result.get('alerts', [])
    files_info = result.get('files_info', {})
    manager_running = result.get('manager_running', False)
    
    # ---------------------------------------------------------
    # Criterion 1: Configuration Check (50 points)
    # ---------------------------------------------------------
    realtime_enabled = False
    ignore_rules_correct = False
    
    # Parse XML loosely (sometimes agents break valid XML, try regex fallback if parse fails)
    try:
        # Wrap in fake root if needed, though ossec.conf usually has <ossec_config>
        if not config_content.strip().startswith('<'):
             raise ValueError("Not XML")
        
        # Simple regex check for realtime
        # Look for <directories ... realtime="yes">.../var/ossec/etc...</directories>
        # Normalized check:
        # 1. Find the directories block containing /var/ossec/etc
        # 2. Check if that block has realtime="yes"
        
        if re.search(r'<directories[^>]*realtime="yes"[^>]*>.*\/var\/ossec\/etc.*<\/directories>', config_content, re.DOTALL):
            realtime_enabled = True
        elif re.search(r'<directories[^>]*>.*\/var\/ossec\/etc.*<\/directories>', config_content, re.DOTALL):
            # Check if attributes were set separately or strict XML parsing needed
            pass
            
        # Regex check for ignore sregex
        # Expect: <ignore type="sregex">.swp$</ignore> or similar
        # Allowed patterns: \.swp$, .swp$, \.tmp$, .tmp$
        if re.search(r'<ignore type="sregex">.*(\.swp|\.tmp).*<\/ignore>', config_content):
            ignore_rules_correct = True
            
    except Exception as e:
        feedback.append(f"Config parsing warning: {e}")

    if realtime_enabled:
        score += 25
        feedback.append("Realtime monitoring enabled for /var/ossec/etc.")
    else:
        feedback.append("Realtime monitoring NOT found for /var/ossec/etc.")

    if ignore_rules_correct:
        score += 25
        feedback.append("Ignore rules (sregex) for .swp/.tmp found.")
    else:
        feedback.append("Ignore rules for .swp/.tmp NOT found or incorrect type.")

    # ---------------------------------------------------------
    # Criterion 2: Test Files Verification (10 points)
    # ---------------------------------------------------------
    pos_file = files_info.get('test_alert.xml', {})
    neg_file = files_info.get('vim_noise.swp', {})
    
    files_created = pos_file.get('exists', False) and neg_file.get('exists', False)
    
    if files_created:
        score += 10
        feedback.append("Test files created successfully.")
    else:
        feedback.append("Test files missing - cannot verify FIM logic.")

    # ---------------------------------------------------------
    # Criterion 3: Alert Logic Verification (40 points)
    # ---------------------------------------------------------
    # We look for syscheck alerts
    # Rule ID 550 (Integrity checksum changed) or 554 (File added)
    # We specifically look for "File added" for test_alert.xml
    
    positive_alert_found = False
    negative_alert_found = False
    
    for alert in alerts:
        rule_group = alert.get('rule', {}).get('groups', [])
        location = alert.get('location', '')
        full_log = alert.get('full_log', '')
        syscheck = alert.get('syscheck', {})
        
        path = syscheck.get('path', '')
        
        # Check for syscheck group
        if 'syscheck' in rule_group:
            if 'test_alert.xml' in path:
                positive_alert_found = True
            if 'vim_noise.swp' in path:
                negative_alert_found = True

    # Scoring Positive Alert
    if positive_alert_found:
        score += 20
        feedback.append("Positive control: Alert generated for test_alert.xml.")
    else:
        feedback.append("Positive control FAIL: No alert for test_alert.xml (Realtime FIM may be broken).")

    # Scoring Negative Alert (Pass if NOT found)
    if files_created and not negative_alert_found:
        score += 20
        feedback.append("Negative control: Noise file ignored correctly.")
    elif not files_created:
        feedback.append("Negative control: Skipped (file not created).")
    else:
        feedback.append("Negative control FAIL: Alert was generated for vim_noise.swp (Ignore rule failed).")

    # ---------------------------------------------------------
    # Final Check
    # ---------------------------------------------------------
    if not manager_running:
        feedback.append("Warning: Wazuh Manager is not running.")
        # We don't deduct points if logs were already captured, but it's bad practice.

    passed = (score >= 70) and realtime_enabled and (files_created and not negative_alert_found)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }