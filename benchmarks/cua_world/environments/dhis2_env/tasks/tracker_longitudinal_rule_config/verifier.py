#!/usr/bin/env python3
"""
Verifier for tracker_longitudinal_rule_config task.

Criteria:
1. Program Rule Variable created for Previous Event (Source: DATAELEMENT_PREVIOUS_EVENT)
2. Program Rule Variable created for Current Event (Source: DATAELEMENT_CURRENT_EVENT)
3. Both variables point to the correct Data Element (Weight)
4. Program Rule created with condition comparing the two variables (Current < Previous)
5. Program Rule Action configured (SHOWWARNING or SHOWERROR)

Scoring:
- Previous Weight Variable: 25 pts
- Current Weight Variable: 15 pts
- Program Rule Created: 20 pts
- Logic Condition Correct: 20 pts
- Action Configured: 20 pts
"""

import json
import tempfile
import os
import logging
import datetime

logger = logging.getLogger(__name__)

def parse_dhis2_date(date_str):
    """Parse DHIS2 ISO format date."""
    try:
        # Handles 2023-10-27T10:00:00.123 and 2023-10-27T10:00:00
        return datetime.datetime.fromisoformat(date_str.replace('Z', '+00:00'))
    except ValueError:
        try:
            # Fallback for older python or slightly different formats
            return datetime.datetime.strptime(date_str.split('.')[0], "%Y-%m-%dT%H:%M:%S")
        except:
            return datetime.datetime.min

def verify_tracker_longitudinal_rule_config(traj, env_info, task_info):
    """Verify DHIS2 configuration for longitudinal weight check."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load result file
    temp_path = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/longitudinal_rule_result.json", temp_path)
        with open(temp_path, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    # Extract data
    task_start_str = data.get("task_start_iso", "")
    target_de_id = data.get("target_data_element_id", "")
    variables = data.get("variables", {}).get("programRuleVariables", [])
    rules = data.get("rules", {}).get("programRules", [])
    
    task_start = parse_dhis2_date(task_start_str)
    
    score = 0
    feedback_parts = []
    
    # Track found items to verify logic later
    found_prev_var_name = None
    found_curr_var_name = None
    
    # 1. Verify Variables
    prev_var_found = False
    curr_var_found = False
    
    for var in variables:
        # Check creation time (allow small clock skew or pre-existing if exactly matches reqs, 
        # but task implies creating new. strict check on creation time is safer for anti-gaming)
        created_str = var.get("created", "")
        created_dt = parse_dhis2_date(created_str)
        
        # We generally expect items to be created after task start.
        # However, if the agent re-uses an existing one that fits exactly, we might accept it 
        # BUT the task instruction says "Create a variable".
        if created_dt < task_start:
            continue
            
        source_type = var.get("programRuleVariableSourceType")
        de_id = var.get("dataElement", {}).get("id")
        name = var.get("name")
        
        if de_id == target_de_id:
            if source_type == "DATAELEMENT_PREVIOUS_EVENT":
                prev_var_found = True
                found_prev_var_name = name
            elif source_type == "DATAELEMENT_CURRENT_EVENT":
                curr_var_found = True
                found_curr_var_name = name
                
    if prev_var_found:
        score += 25
        feedback_parts.append("✅ 'Previous Weight' variable created")
    else:
        feedback_parts.append("❌ 'Previous Weight' variable not found (Source: Data element from previous event)")

    if curr_var_found:
        score += 15
        feedback_parts.append("✅ 'Current Weight' variable created")
    else:
        feedback_parts.append("❌ 'Current Weight' variable not found (Source: Data element in current event)")

    # 2. Verify Rule
    rule_found = False
    logic_correct = False
    action_correct = False
    
    for rule in rules:
        created_str = rule.get("created", "")
        created_dt = parse_dhis2_date(created_str)
        
        if created_dt < task_start:
            continue
            
        rule_found = True
        condition = rule.get("condition", "")
        actions = rule.get("programRuleActions", [])
        
        # Check Logic
        # Robust check: look for presence of both variable names and a less-than symbol
        if found_prev_var_name and found_curr_var_name:
            # Need to handle variable syntax: usually #{VariableName} or A{VariableName} or just name depending on API version
            # The API usually returns the raw condition string e.g. "#{CurrentWeight} < #{PreviousWeight}"
            
            # Simple heuristic: check if variable names appear in condition
            has_prev = found_prev_var_name in condition
            has_curr = found_curr_var_name in condition
            has_lt = "<" in condition
            
            if has_prev and has_curr and has_lt:
                logic_correct = True
        
        # Check Action
        for action in actions:
            act_type = action.get("programRuleActionType")
            act_de = action.get("dataElement", {}).get("id")
            
            if act_type in ["SHOWWARNING", "SHOWERROR"]:
                # Ideally acts on the weight field, but general warning is okay for partial credit
                action_correct = True
                break
        
        if logic_correct and action_correct:
            break # Found the perfect rule, stop searching

    if rule_found:
        score += 20
        feedback_parts.append("✅ Program Rule created")
    else:
        feedback_parts.append("❌ No new Program Rule found")

    if logic_correct:
        score += 20
        feedback_parts.append("✅ Rule condition logic is correct (Current < Previous)")
    elif rule_found:
        feedback_parts.append("❌ Rule condition incorrect. Expected comparison of the two variables.")

    if action_correct:
        score += 20
        feedback_parts.append("✅ Rule action configured (Warning/Error)")
    elif rule_found:
        feedback_parts.append("❌ Rule action incorrect. Expected 'Show warning' or 'Show error'.")

    passed = score >= 60 and prev_var_found and rule_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }