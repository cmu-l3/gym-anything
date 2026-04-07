#!/usr/bin/env python3
"""
Verifier for Detect Rapid Data Destruction task.

Checks:
1. Manager is running.
2. ossec.conf has FIM enabled with realtime="yes" for the specific directory.
3. local_rules.xml has Rule 100250 with correct frequency, timeframe, and parent SID.
4. Functional test passed (alert actually triggered during simulation).
"""

import json
import os
import base64
import re
import logging
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_rapid_data_destruction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    target_dir = metadata.get('target_dir', '/var/ossec/data/financial_records')
    expected_rule_id = str(metadata.get('rule_id', 100250))
    expected_frequency = str(metadata.get('frequency', 5))
    expected_timeframe = str(metadata.get('timeframe', 45))
    mitre_id = metadata.get('mitre_id', 'T1485')

    score = 0
    feedback = []
    
    # 1. Check if Manager is Running (Pre-requisite)
    if result.get('manager_running', False):
        score += 10
        feedback.append("Wazuh manager is running.")
    else:
        feedback.append("Wazuh manager is NOT running.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 2. Check ossec.conf for FIM configuration
    ossec_conf_b64 = result.get('ossec_conf_b64', '')
    fim_configured = False
    realtime_enabled = False
    
    if ossec_conf_b64:
        try:
            ossec_conf = base64.b64decode(ossec_conf_b64).decode('utf-8')
            # XML parsing is fragile if file is malformed, using regex/robust parsing
            # Look for <directories ...>target_dir</directories>
            # Clean up newlines for regex
            clean_conf = re.sub(r'\s+', ' ', ossec_conf)
            
            # Regex to find the directory block
            # Matches <directories ...>.../financial_records...</directories>
            dir_match = re.search(r'<directories([^>]*)>([^<]*' + re.escape(target_dir) + r'[^<]*)</directories>', clean_conf)
            
            if dir_match:
                fim_configured = True
                attrs = dir_match.group(1)
                content = dir_match.group(2)
                
                if 'realtime="yes"' in attrs or "realtime='yes'" in attrs:
                    realtime_enabled = True
                
                # Check if checking is enabled (check_all or explicit)
                if 'check_all="yes"' in attrs or 'check_all="yes"' in attrs:
                    pass # Good
            else:
                feedback.append(f"Directory {target_dir} not found in ossec.conf.")

        except Exception as e:
            feedback.append(f"Error parsing ossec.conf: {str(e)}")

    if fim_configured:
        score += 15
        feedback.append("FIM configured for target directory.")
    else:
        feedback.append("FIM NOT configured correctly.")

    if realtime_enabled:
        score += 15
        feedback.append("Real-time monitoring enabled.")
    else:
        feedback.append("Real-time monitoring NOT enabled (required for rapid detection).")

    # 3. Check local_rules.xml for Correlation Rule
    local_rules_b64 = result.get('local_rules_b64', '')
    rule_found = False
    rule_correct = False
    mitre_found = False
    
    if local_rules_b64:
        try:
            local_rules = base64.b64decode(local_rules_b64).decode('utf-8')
            root = ET.fromstring(f"<root>{local_rules}</root>") # Wrap in root in case multiple top-level elements
            
            # Find rule with ID 100250
            # Note: local_rules usually inside a <group> tag
            for rule in root.findall(".//rule"):
                if rule.get('id') == expected_rule_id:
                    rule_found = True
                    
                    # Check attributes
                    freq = rule.get('frequency')
                    timeframe = rule.get('timeframe')
                    level = rule.get('level')
                    
                    if freq == expected_frequency and timeframe == expected_timeframe:
                        if int(level) >= 12:
                            rule_correct = True
                        else:
                            feedback.append(f"Rule level {level} is too low (expected >= 12).")
                    else:
                        feedback.append(f"Rule timing incorrect: found freq={freq}/time={timeframe}, expected {expected_frequency}/{expected_timeframe}.")
                    
                    # Check Logic (if_matched_sid)
                    if_sid = rule.find('if_matched_sid')
                    if if_sid is not None and if_sid.text == '553':
                        pass # Good
                    elif rule.find('if_sid') is not None and rule.find('if_sid').text == '553':
                         # Sometimes users use if_sid for single event, but frequency requires correlation
                         # For frequency based on previous rule, usually if_matched_sid is used
                         pass 
                    else:
                        feedback.append("Rule parent logic incorrect (should trigger on SID 553).")

                    # Check MITRE
                    mitre = rule.find(".//mitre/id")
                    if mitre is not None and mitre_id in mitre.text:
                        mitre_found = True
                    break
                    
        except Exception as e:
            feedback.append(f"Error parsing local_rules.xml: {str(e)}")

    if rule_found:
        score += 10
        feedback.append(f"Rule {expected_rule_id} created.")
    else:
        feedback.append(f"Rule {expected_rule_id} NOT found.")

    if rule_correct:
        score += 20
        feedback.append("Rule logic (frequency/timeframe) correct.")

    if mitre_found:
        score += 10
        feedback.append(f"MITRE ID {mitre_id} mapped correctly.")

    # 4. Functional Test (The "Live Fire" simulation)
    # The export_result.sh script attempted to trigger the alert.
    alert_triggered = result.get('alert_triggered', False)
    
    if alert_triggered:
        score += 30
        feedback.append("Functional Test PASSED: Alert triggered during simulation.")
    else:
        feedback.append("Functional Test FAILED: Alert did not trigger during simulation.")
        # If config looks good but alert failed, it might be a restart issue or wait time
        if fim_configured and realtime_enabled and rule_correct:
             feedback.append("(Logic seems correct, possibly service restart or timing issue)")

    passed = (score >= 70) and alert_triggered

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }