#!/usr/bin/env python3
"""
Verifier for create_correlated_attack_rules task.
Verifies Wazuh custom rules for multi-stage attack detection.
"""

import json
import os
import xml.etree.ElementTree as ET
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correlated_rules(traj, env_info, task_info):
    """
    Verify the creation and loading of 3 correlated Wazuh rules.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_rules = metadata.get('required_rules', [])

    # Temp files for artifacts
    temp_rules_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    temp_api_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_agent_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    score = 0
    feedback = []
    
    try:
        # Copy files from environment
        copy_from_env("/tmp/local_rules.xml", temp_rules_xml.name)
        copy_from_env("/tmp/api_rules_check.json", temp_api_json.name)
        copy_from_env("/tmp/agent_verification.json", temp_agent_json.name)
        copy_from_env("/tmp/task_result.json", temp_result_json.name)

        # Load task result metadata
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)

        # --- CRITERION 1: Manager Running (5 pts) ---
        if task_result.get("manager_running", False):
            score += 5
            feedback.append("Wazuh manager is running")
        else:
            feedback.append("Wazuh manager is NOT running (critical failure)")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

        # --- CRITERION 2: API Verification (Active State) (45 pts) ---
        # Checks if rules are actually loaded in the engine
        loaded_rules = {}
        try:
            with open(temp_api_json.name, 'r') as f:
                api_data = json.load(f)
                items = api_data.get('data', {}).get('affected_items', [])
                for item in items:
                    loaded_rules[int(item['id'])] = item
        except json.JSONDecodeError:
            feedback.append("Failed to decode API response")

        for req in required_rules:
            rid = req['id']
            if rid in loaded_rules:
                rule_data = loaded_rules[rid]
                # Check level
                if rule_data.get('level') == req['level']:
                    score += 15
                    feedback.append(f"Rule {rid} active with correct level {req['level']}")
                else:
                    score += 5 # Active but wrong level
                    feedback.append(f"Rule {rid} active but wrong level (got {rule_data.get('level')})")
            else:
                feedback.append(f"Rule {rid} NOT found in loaded configuration")

        # --- CRITERION 3: XML Static Analysis (Syntax & Logic) (42 pts) ---
        # Checks the logic that isn't always fully exposed in the basic API response
        try:
            tree = ET.parse(temp_rules_xml.name)
            root = tree.getroot()
            
            # Helper to find rule node
            def find_rule_node(rule_id):
                for rule in root.findall('rule'):
                    if rule.get('id') == str(rule_id):
                        return rule
                return None

            # Rule 100300 Logic
            r1 = find_rule_node(100300)
            if r1 is not None:
                # Check frequency/timeframe
                freq = r1.get('frequency')
                timeframe = r1.get('timeframe')
                if freq == "8" and timeframe == "120":
                    score += 8
                else:
                    feedback.append(f"Rule 100300 timing incorrect (expected freq=8, time=120; got f={freq}, t={timeframe})")
                
                # Check if_matched_sid
                if_matched = r1.find('if_matched_sid')
                if if_matched is not None and if_matched.text == "5710":
                    score += 7
                else:
                    feedback.append("Rule 100300 missing correct if_matched_sid 5710")
            
            # Rule 100301 Logic
            r2 = find_rule_node(100301)
            if r2 is not None:
                # Check chaining
                if_sid = r2.find('if_sid')
                if_matched = r2.find('if_matched_sid')
                
                if if_sid is not None and if_sid.text == "5715" and \
                   if_matched is not None and if_matched.text == "100300":
                    score += 10
                else:
                    feedback.append("Rule 100301 not properly chained (must be if_sid 5715 AND if_matched_sid 100300)")

                # Check same_source_ip
                if r2.find('same_source_ip') is not None:
                    score += 5
                else:
                    feedback.append("Rule 100301 missing same_source_ip correlation")

            # Rule 100302 Logic
            r3 = find_rule_node(100302)
            if r3 is not None:
                # Check chaining
                if_sid = r3.find('if_sid')
                if_matched = r3.find('if_matched_sid')
                
                if if_sid is not None and if_sid.text == "5902" and \
                   if_matched is not None and if_matched.text == "100301":
                    score += 10
                else:
                    feedback.append("Rule 100302 not properly chained (must be if_sid 5902 AND if_matched_sid 100301)")
                
                # Timeframe
                if r3.get('timeframe') == "900":
                    score += 2
                
        except ET.ParseError:
            feedback.append("local_rules.xml contains invalid XML syntax")
        except Exception as e:
            feedback.append(f"Error parsing rules XML: {str(e)}")

        # --- CRITERION 4: Agent Verification File (8 pts) ---
        if task_result.get("verification_file_exists", False):
            # Check if it contains valid JSON with the rule IDs
            try:
                with open(temp_agent_json.name, 'r') as f:
                    content = f.read()
                    if "100300" in content and "100301" in content:
                        score += 8
                        feedback.append("Verification file created and contains rule data")
                    else:
                        score += 4
                        feedback.append("Verification file exists but content is missing required rule IDs")
            except:
                feedback.append("Verification file exists but is invalid")

    except Exception as e:
        feedback.append(f"Verification system error: {str(e)}")
    finally:
        # Cleanup
        for fpath in [temp_rules_xml.name, temp_api_json.name, temp_agent_json.name, temp_result_json.name]:
            if os.path.exists(fpath):
                os.unlink(fpath)

    passed = score >= 60 and all(req['id'] in loaded_rules for req in required_rules)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }