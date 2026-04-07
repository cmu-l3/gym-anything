#!/usr/bin/env python3
"""
Verifier for configure_time_based_suppression task.
Verifies that the agent correctly configured a Wazuh rule with:
- Correct ID and Level
- Correct parent (if_sid)
- Correct user constraint
- Correct time constraint
- Valid XML syntax (Service is running)
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_time_suppression(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_rule_id = metadata.get('target_rule_id', '100250')
    parent_rule_id = metadata.get('parent_rule_id', '5715')
    target_user = metadata.get('target_user', 'backup_svc')
    expected_start = metadata.get('start_time', '02:55')
    expected_end = metadata.get('end_time', '03:30')
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check if Manager is Running (Valid Syntax check)
    if not result.get('manager_running', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Wazuh manager is not running. This usually means the local_rules.xml file has invalid syntax that crashed the service."
        }
    
    score += 10
    feedback_parts.append("Wazuh manager is running (valid XML syntax)")

    # 3. Retrieve and Parse local_rules.xml
    rules_remote_path = result.get('rules_file_path', '/tmp/submitted_rules.xml')
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    
    try:
        copy_from_env(rules_remote_path, temp_xml.name)
        
        # Parse XML
        try:
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
        except ET.ParseError as e:
            return {"passed": False, "score": score, "feedback": f"Failed to parse local_rules.xml: {e}"}
            
        # Find the target rule
        # Rules can be directly under root or inside a group
        found_rule = None
        for rule in root.iter('rule'):
            if rule.get('id') == target_rule_id:
                found_rule = rule
                break
        
        if not found_rule:
            return {
                "passed": False, 
                "score": score, 
                "feedback": f"Rule ID {target_rule_id} not found in local_rules.xml"
            }
        
        score += 20
        feedback_parts.append(f"Rule {target_rule_id} created")

        # 4. Check Level (Should be 0 for suppression)
        level = found_rule.get('level')
        if level == '0':
            score += 20
            feedback_parts.append("Level set to 0 (suppression)")
        else:
            feedback_parts.append(f"Incorrect level: {level} (expected 0)")

        # 5. Check Parent (if_sid)
        if_sid_elem = found_rule.find('if_sid')
        if if_sid_elem is not None and str(parent_rule_id) in if_sid_elem.text:
            score += 15
            feedback_parts.append(f"Correct parent rule ({parent_rule_id})")
        else:
            feedback_parts.append(f"Missing or incorrect <if_sid> (expected {parent_rule_id})")

        # 6. Check User Constraint
        # <user>backup_svc</user> or <match>...backup_svc...</match>? 
        # Standard way is <user>
        user_elem = found_rule.find('user')
        if user_elem is not None and target_user in user_elem.text:
            score += 15
            feedback_parts.append(f"Correct user constraint ({target_user})")
        else:
            feedback_parts.append(f"Missing or incorrect <user> tag (expected {target_user})")

        # 7. Check Time Constraint
        # <time>2:55-3:30</time>
        # Wazuh accepts various formats, we should be slightly flexible but strict on values
        time_elem = found_rule.find('time')
        if time_elem is not None:
            time_text = time_elem.text.strip()
            # Normalize user input (e.g. 02:55 vs 2:55)
            # Remove spaces
            time_text = time_text.replace(" ", "")
            
            # Simple check: does it contain start and end?
            # 02:55-03:30 or 2:55-3:30
            
            # Function to normalize "02:55" to "2:55"
            def normalize_time(t):
                if ':' in t:
                    h, m = t.split(':')
                    return f"{int(h)}:{m}" # 2:55
                return t

            try:
                if '-' in time_text:
                    start, end = time_text.split('-')
                    norm_start = normalize_time(start)
                    norm_end = normalize_time(end)
                    exp_start = normalize_time(expected_start)
                    exp_end = normalize_time(expected_end)
                    
                    if norm_start == exp_start and norm_end == exp_end:
                        score += 20
                        feedback_parts.append(f"Correct time window ({expected_start}-{expected_end})")
                    else:
                        feedback_parts.append(f"Incorrect time range: {time_text} (expected {expected_start}-{expected_end})")
                else:
                    feedback_parts.append("Invalid time format (missing '-')")
            except:
                 feedback_parts.append("Error parsing time format")
        else:
            feedback_parts.append("Missing <time> tag")

    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    passed = (score >= 90) # Requires almost perfection
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }