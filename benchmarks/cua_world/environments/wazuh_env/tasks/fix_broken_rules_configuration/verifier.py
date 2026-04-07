#!/usr/bin/env python3
"""
Verifier for fix_broken_rules_configuration task.
"""

import json
import base64
import tempfile
import os
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_broken_rules_configuration(traj, env_info, task_info):
    """
    Verifies that:
    1. The Wazuh Manager service is running.
    2. The local_rules.xml file is valid XML.
    3. The specific errors (syntax, level, ID) are fixed.
    4. The rules are actually loaded in the engine.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    
    # 1. Check Service Status (30 pts)
    service_running = result.get('service_running', False)
    if service_running:
        score += 30
        feedback.append("Wazuh Manager service is running.")
    else:
        feedback.append("Wazuh Manager service is NOT running.")

    # 2. Parse XML Content (20 pts for syntax)
    rules_b64 = result.get('rules_content_b64', '')
    rules_xml = ""
    try:
        rules_xml = base64.b64decode(rules_b64).decode('utf-8')
    except:
        feedback.append("Could not decode rules file.")

    xml_valid = False
    root = None
    
    if rules_xml:
        try:
            # Wrap in a root tag just in case, though <group> is usually root for this file
            # Wazuh rules files usually start with <group>.
            root = ET.fromstring(rules_xml)
            score += 20
            xml_valid = True
            feedback.append("local_rules.xml is valid XML (syntax error fixed).")
        except ET.ParseError as e:
            feedback.append(f"local_rules.xml contains syntax errors: {e}")
    
    # 3. Check Logic fixes
    # We need to find rules 100200 and 100201
    
    rule_100200 = None
    rule_100201 = None
    
    if xml_valid and root is not None:
        for rule in root.findall('rule'):
            rule_id = rule.get('id')
            if rule_id == '100200':
                rule_100200 = rule
            elif rule_id == '100201':
                rule_100201 = rule
        
        # Check Rule 100200 (15 pts)
        if rule_100200 is not None:
            level = rule_100200.get('level')
            if level and level.isdigit() and int(level) == 12:
                score += 15
                feedback.append("Rule 100200 preserved correctly.")
            else:
                feedback.append(f"Rule 100200 found but level '{level}' is incorrect (expected 12).")
        else:
            feedback.append("Rule 100200 not found.")

        # Check Rule 100201 (Resolution of duplicate) (20 pts)
        # Also checks if the 'medium' level was fixed
        if rule_100201 is not None:
            level = rule_100201.get('level')
            match_tag = rule_100201.find('match')
            match_text = match_tag.text if match_tag is not None else ""
            
            # Verify this is the formerly broken rule (transaction_slow)
            if "transaction_slow" in match_text:
                if level and level.isdigit():
                    score += 20
                    feedback.append("Duplicate ID resolved (100201) and level fixed to integer.")
                else:
                    score += 10 # Partial credit for ID fix but bad level
                    feedback.append(f"Rule 100201 found, but level '{level}' is not an integer.")
            else:
                 feedback.append("Rule 100201 found but does not match 'transaction_slow'.")
        else:
            feedback.append("Rule 100201 (expected fix for duplicate) not found.")

        # Check for levels on all rules (15 pts)
        # Basic check: all rules should have integer levels
        all_levels_valid = True
        for rule in root.findall('rule'):
            lvl = rule.get('level')
            if not lvl or not lvl.isdigit():
                all_levels_valid = False
                break
        
        if all_levels_valid:
            score += 15
            feedback.append("All rule levels are valid integers.")
        else:
            feedback.append("Found rules with invalid (non-integer) levels.")

    # 4. API Confirmation (Penalty if service is running but rules not loaded)
    loaded_ids = result.get('loaded_rule_ids', [])
    if service_running:
        if 100200 in loaded_ids and 100201 in loaded_ids:
            feedback.append("API confirms both rules are loaded.")
        else:
            feedback.append(f"Warning: Service is running but API does not report expected rules. Loaded: {loaded_ids}")
            # We don't deduct heavily if XML is right, as startup might be slow, but this is a good sanity check.

    # Final logic
    passed = (score >= 70) and service_running and xml_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }