#!/usr/bin/env python3
"""
Verifier for detect_impossible_travel task.

Verifies:
1. Static analysis of local_rules.xml for correct Rule ID, logic, and attributes.
2. Dynamic analysis of alerts.json to confirm the alert was actually triggered.
"""

import json
import os
import sys
import xml.etree.ElementTree as ET
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_impossible_travel(traj, env_info, task_info):
    """
    Verify the Impossible Travel rule implementation and execution.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_rule_id = metadata.get('rule_id', '100050')
    
    score = 0
    feedback = []
    
    # ------------------------------------------------------------------
    # Step 1: Retrieve files
    # ------------------------------------------------------------------
    local_rules_path = "/tmp/verifier_local_rules.xml"
    alerts_json_path = "/tmp/verifier_alerts.json"
    task_result_path = "/tmp/verifier_task_result.json"
    
    try:
        copy_from_env("/tmp/local_rules.xml", local_rules_path)
        copy_from_env("/tmp/alerts.json", alerts_json_path)
        copy_from_env("/tmp/task_result.json", task_result_path)
        
        with open(task_result_path, 'r') as f:
            task_result = json.load(f)
            
        task_start_ts = task_result.get("task_start_timestamp", 0)
        manager_running = task_result.get("manager_running", False)
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task files: {str(e)}"}

    # ------------------------------------------------------------------
    # Step 2: Verify Rule Structure (Static Analysis) - 50 Points
    # ------------------------------------------------------------------
    rule_found = False
    rule_correct = False
    
    if os.path.exists(local_rules_path) and os.path.getsize(local_rules_path) > 0:
        try:
            # Wazuh rules files are XML fragments, usually wrapped in <group>.
            # If the file doesn't have a single root, we might need to wrap it.
            # local_rules.xml usually starts with <group name="local,">
            tree = ET.parse(local_rules_path)
            root = tree.getroot()
            
            # Find our rule
            # Search recursively
            target_rule = None
            for rule in root.findall(".//rule"):
                if rule.get("id") == target_rule_id:
                    target_rule = rule
                    break
            
            if target_rule is not None:
                score += 20
                feedback.append(f"Rule {target_rule_id} found in local_rules.xml.")
                rule_found = True
                
                # Check attributes
                freq = target_rule.get("frequency")
                timeframe = target_rule.get("timeframe")
                level = target_rule.get("level")
                
                # Check frequency (expect 2)
                if freq == "2":
                    score += 5
                else:
                    feedback.append(f"Incorrect frequency: expected 2, got {freq}")

                # Check timeframe (expect 60, allow small tolerance if they changed it slightly)
                if timeframe and 40 <= int(timeframe) <= 120:
                    score += 5
                else:
                    feedback.append(f"Incorrect timeframe: expected 60, got {timeframe}")
                
                # Check level (expect 12 or high)
                if level and int(level) >= 10:
                    score += 5
                else:
                    feedback.append(f"Alert level too low: {level}")

                # Check logic tags
                # We need <same_user /> and <different_srcip />
                has_same_user = target_rule.find("same_user") is not None
                has_diff_ip = target_rule.find("different_srcip") is not None
                
                if has_same_user:
                    score += 5
                else:
                    feedback.append("Missing <same_user /> tag.")
                    
                if has_diff_ip:
                    score += 5
                else:
                    feedback.append("Missing <different_srcip /> tag.")
                    
                # Check parent dependency
                # usually <if_sid>5715</if_sid> OR <if_matched_sid>
                if_sid = target_rule.find("if_sid")
                if_matched_sid = target_rule.find("if_matched_sid")
                
                parent_ok = False
                if if_sid is not None and if_sid.text == "5715":
                    parent_ok = True
                elif if_matched_sid is not None and if_matched_sid.text == "5715":
                    parent_ok = True
                
                if parent_ok:
                    score += 5
                else:
                    feedback.append("Parent rule (5715) not correctly referenced.")

            else:
                feedback.append(f"Rule {target_rule_id} not found in local_rules.xml.")
                
        except ET.ParseError:
            feedback.append("local_rules.xml contains invalid XML syntax.")
    else:
        feedback.append("local_rules.xml is missing or empty.")

    # ------------------------------------------------------------------
    # Step 3: Verify Alert Generation (Dynamic Analysis) - 50 Points
    # ------------------------------------------------------------------
    alert_found = False
    
    if os.path.exists(alerts_json_path):
        try:
            with open(alerts_json_path, 'r') as f:
                # alerts.json is one JSON object per line
                for line in f:
                    try:
                        alert = json.loads(line)
                        rule_data = alert.get("rule", {})
                        
                        # Check if this is our rule
                        if str(rule_data.get("id")) == target_rule_id:
                            # Check timestamp to ensure it's from this session
                            # Wazuh timestamp format: "2023-10-27T10:00:00.000+0000"
                            alert_ts_str = alert.get("timestamp")
                            # Simple string comparison is risky, but works if format is ISO8601
                            # Better: check file mtime or trust clean env
                            # For robustness, we'll assume if it's in the tail of logs during verification, it's new
                            # provided we verify task_start_ts vs file modification, but we are reading content here.
                            
                            # Since we cleaned up the rule in setup_task.sh, any firing of this rule ID
                            # MUST be from this session.
                            alert_found = True
                            score += 50
                            feedback.append("Alert triggered successfully.")
                            break
                    except json.JSONDecodeError:
                        continue
        except Exception as e:
            feedback.append(f"Error reading alerts.json: {e}")
    
    if not alert_found:
        feedback.append("No alert found for rule 100050. Did you restart the manager and simulate the attack?")

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    passed = (score >= 70) and rule_found and alert_found
    
    # Clean up temp files
    for p in [local_rules_path, alerts_json_path, task_result_path]:
        if os.path.exists(p):
            os.remove(p)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }