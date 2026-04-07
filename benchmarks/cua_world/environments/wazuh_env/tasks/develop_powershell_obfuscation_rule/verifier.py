#!/usr/bin/env python3
import json
import re
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_develop_powershell_obfuscation_rule(traj, env_info, task_info):
    """
    Verifies the PowerShell obfuscation detection rule task.
    
    Criteria:
    1. Rule 100300 exists in local_rules.xml (20 pts)
    2. Rule has correct level (10) and basic structure (10 pts)
    3. Regex pattern is robust and targets encoded flags (30 pts)
    4. wazuh-logtest output confirms the rule triggers on the sample (30 pts)
    5. Wazuh manager is running (10 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check Manager Status
    if result.get('manager_running'):
        score += 10
        feedback.append("Wazuh manager is running.")
    else:
        feedback.append("Wazuh manager is NOT running.")

    # 2. Parse XML and Check Rule Existence
    rules_content = result.get('rules_content', '')
    if not rules_content:
        return {"passed": False, "score": score, "feedback": "local_rules.xml is empty or unreadable."}

    # Wrap in root element if missing (local_rules often just has group)
    if not rules_content.strip().startswith('<ossec_config>') and not rules_content.strip().startswith('<group'):
        # Sometimes user might write partial xml
        pass
    
    # Parse XML
    try:
        # local_rules.xml typically starts with <group name="...">
        # We wrap it in a dummy root to ensure valid XML parsing if needed, 
        # but usually ElementTree can handle the group tag as root.
        root = ET.fromstring(rules_content)
        
        # Find rule 100300
        # Search recursively for rule with id="100300"
        rule_node = None
        for rule in root.iter('rule'):
            if rule.get('id') == '100300':
                rule_node = rule
                break
        
        if rule_node is not None:
            score += 20
            feedback.append("Rule 100300 found in local_rules.xml.")
            
            # Check Level
            level = rule_node.get('level')
            if level == '10':
                score += 10
                feedback.append("Rule level is correct (10).")
            else:
                feedback.append(f"Rule level is {level}, expected 10.")
            
            # Extract Regex
            # <regex>...</regex> or <field ... type="pcre2">...</field>
            # Wazuh rules often use <regex> or <match> or <field>
            regex_pattern = ""
            for child in rule_node:
                if child.tag == 'regex':
                    regex_pattern = child.text
                elif child.tag == 'field':
                    regex_pattern = child.text
            
            if regex_pattern:
                feedback.append(f"Found regex pattern: {regex_pattern}")
                
                # 3. Verify Regex Quality
                # We test the user's regex against test cases using Python's re
                # Note: Wazuh uses OS_Regex (similar to basic regex) or PCRE2.
                # We assume standard regex behavior for verification.
                
                # Metadata requirements
                required_matches = task_info['metadata']['required_regex_matches']
                
                # Check case insensitivity flag in Wazuh regex often handled by (?i) or just being standard
                # If user didn't put (?i), Wazuh regex is case sensitive by default unless type="pcre2" (?i) is used
                # We will compile with re.IGNORECASE if the user's regex doesn't explicitly look like it handles it
                
                try:
                    # Clean up pattern (Wazuh XML might have whitespace)
                    clean_pattern = regex_pattern.strip()
                    re_pat = re.compile(clean_pattern, re.IGNORECASE) 
                    
                    matches_all = True
                    for test_str in required_matches:
                        if not re_pat.search(test_str):
                            matches_all = False
                            feedback.append(f"Regex failed to match: {test_str}")
                    
                    if matches_all:
                        score += 30
                        feedback.append("Regex matches all required obfuscation patterns.")
                    else:
                        score += 10 # Partial credit for having a regex
                except re.error:
                    feedback.append("Invalid regex syntax.")
            else:
                feedback.append("No <regex> or <field> tag found in rule.")
                
        else:
            feedback.append("Rule ID 100300 NOT found in local_rules.xml.")

    except ET.ParseError:
        feedback.append("Failed to parse local_rules.xml - invalid XML syntax.")

    # 4. Check Logtest Output (The ultimate truth)
    # If the rule actually works in Wazuh, it will appear in the output
    logtest_output = result.get('logtest_output', '')
    
    # We look for:
    # ** Phase 3: Completed filtering (rules).
    #       Rule id: '100300'
    #       Level: '10'
    
    if "Rule id: '100300'" in logtest_output or 'Rule id: "100300"' in logtest_output:
        score += 30
        feedback.append("wazuh-logtest confirmed rule 100300 triggered on the sample.")
    else:
        feedback.append("wazuh-logtest did NOT trigger rule 100300 on the sample log.")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }