#!/usr/bin/env python3
"""
Verifier for tracker_bmi_program_rule_config task.

Scoring (100 points total):
1. BMI Data Element created (Number type) - 10 pts
2. Assigned to correct Program Stage - 10 pts
3. Program Rule Variables for Weight/Height - 20 pts
4. Calculation Rule (Assign BMI) exists with valid formula - 25 pts
5. Warning Rule (< 18.5) exists - 15 pts
6. Assign Action targets correct DE - 10 pts
7. Evidence Screenshot exists - 10 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_tracker_bmi_program_rule_config(traj, env_info, task_info):
    """Verify DHIS2 BMI configuration."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        copy_from_env("/tmp/bmi_config_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {e}"}

    score = 0
    feedback = []
    
    task_start_iso = result.get('task_start_iso', '')
    
    # 1. Verify Data Element (10 pts)
    # Look for a numeric data element containing "BMI" created recently-ish (or at least existing)
    de_list = result.get('data_elements_found', [])
    bmi_de = None
    
    for de in de_list:
        name = de.get('name', '').lower()
        if 'bmi' in name and 'calc' in name:
            if de.get('valueType') in ['NUMBER', 'INTEGER', 'Coordinate']: # Coordinate sometimes used by mistake, but NUMBER is correct
                bmi_de = de
                break
    
    # Fallback: if they named it just "BMI"
    if not bmi_de:
        for de in de_list:
            if 'bmi' in de.get('name', '').lower() and de.get('valueType') == 'NUMBER':
                bmi_de = de
                break

    if bmi_de:
        score += 10
        feedback.append(f"Data Element '{bmi_de['name']}' found.")
    else:
        feedback.append("Data Element 'BMI (Calculated)' not found or incorrect type.")

    # 2. Verify Assignment to Program Stage (10 pts)
    stage_de_ids = result.get('stage_data_elements', [])
    if bmi_de and bmi_de['id'] in stage_de_ids:
        score += 10
        feedback.append("Data Element assigned to ANC Program Stage.")
    elif bmi_de:
        feedback.append("Data Element NOT assigned to ANC Program Stage.")
    else:
        feedback.append("Cannot verify stage assignment (DE missing).")

    # 3. Verify Program Rule Variables (20 pts)
    # Need variables for Weight and Height
    prv_list = result.get('program_rule_variables', [])
    has_weight_var = False
    has_height_var = False
    
    for prv in prv_list:
        name = prv.get('name', '').lower()
        de_name = prv.get('dataElement', {}).get('name', '').lower()
        
        if 'weight' in name or 'weight' in de_name:
            has_weight_var = True
        if 'height' in name or 'height' in de_name:
            has_height_var = True
            
    if has_weight_var and has_height_var:
        score += 20
        feedback.append("Program Rule Variables for Weight and Height found.")
    elif has_weight_var or has_height_var:
        score += 10
        feedback.append("Only one of Weight/Height variables found.")
    else:
        feedback.append("Program Rule Variables for Weight/Height missing.")

    # 4. Verify Calculation Rule (25 pts) + 6. Assign Action (10 pts)
    pr_list = result.get('program_rules', [])
    calc_rule_found = False
    assign_action_found = False
    valid_formula = False
    
    for pr in pr_list:
        actions = pr.get('programRuleActions', [])
        for action in actions:
            # Check for ASSIGN action
            if action.get('programRuleActionType') == 'ASSIGN':
                target_de = action.get('dataElement', {}).get('id', '')
                data_expr = action.get('data', '').replace(' ', '')
                
                # Check if it targets our BMI DE
                if bmi_de and target_de == bmi_de['id']:
                    assign_action_found = True
                    calc_rule_found = True
                    
                    # Rough check for formula structure: weight / (height*height)
                    # Common var names: #{weight}, #{height}, A{weight}
                    if '/' in data_expr and ('^2' in data_expr or '*' in data_expr):
                        valid_formula = True
                
                # Fallback check if we missed the DE link but formula looks like BMI
                elif '100' in data_expr and '/' in data_expr:
                     calc_rule_found = True
                     if bmi_de: # Maybe they assigned to something else?
                         pass 
                         
    if calc_rule_found:
        score += 15 # Base points for rule existence
        feedback.append("BMI Calculation rule found.")
        if valid_formula:
            score += 10
            feedback.append("BMI Formula appears valid.")
        else:
            feedback.append("BMI Formula might be incorrect (check cm conversion).")
    else:
        feedback.append("No BMI Calculation rule found.")
        
    if assign_action_found:
        score += 10
        feedback.append("Rule correctly assigns to BMI Data Element.")

    # 5. Verify Warning Rule (15 pts)
    warning_found = False
    for pr in pr_list:
        condition = pr.get('condition', '').replace(' ', '')
        # Check condition like #{bmi} < 18.5
        if '<18.5' in condition or '<=18.5' in condition:
            actions = pr.get('programRuleActions', [])
            for action in actions:
                atype = action.get('programRuleActionType')
                if atype in ['SHOWWARNING', 'SHOWERROR']:
                    warning_found = True
                    break
    
    if warning_found:
        score += 15
        feedback.append("Underweight Warning rule found.")
    else:
        feedback.append("No Warning rule for BMI < 18.5 found.")

    # 7. Screenshot (10 pts)
    if result.get('screenshot_exists', False):
        score += 10
        feedback.append("Verification screenshot provided.")
    else:
        feedback.append("No screenshot found.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }