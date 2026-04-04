#!/usr/bin/env python3
"""
Verifier for program_rule_data_quality task.

Scoring (100 points total):
1. Program rule variable created (15 pts) [MANDATORY]
2. Variable linked to data element/attribute (10 pts)
3. Rule #1 (Weight Out of Range) created (20 pts)
4. Rule #1 has valid condition (10 pts)
5. Rule #1 has warning action (10 pts)
6. Rule #2 (Low Birth Weight) created (15 pts)
7. Rule #2 has valid condition (5 pts)
8. Rule #2 has warning action (5 pts)
9. Both rules associated with correct programme (10 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_program_rule_data_quality(traj, env_info, task_info):
    """Verify creation of program rules for data quality."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/task_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)
    except Exception as e:
         return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}

    score = 0
    feedback_parts = []
    
    # Extract data
    new_vars = result.get('new_variables', [])
    new_rules = result.get('new_rules', [])
    
    # 1. Check Variable (Mandatory)
    variable_created = False
    variable_linked = False
    
    # Look for 'child_weight' or similar
    target_var = None
    for v in new_vars:
        name = v.get('name', '').lower()
        if 'weight' in name:
            target_var = v
            variable_created = True
            break
    
    # If not found by name, take the first new variable
    if not target_var and new_vars:
        target_var = new_vars[0]
        variable_created = True
        
    if not variable_created:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new program rule variable found. You must create a variable for weight."
        }
        
    score += 15
    feedback_parts.append("Variable created (+15)")
    
    # Check linkage
    if target_var:
        source_type = target_var.get('programRuleVariableSourceType', '')
        # Should be DATAELEMENT_... or TEI_ATTRIBUTE
        if 'DATAELEMENT' in source_type or 'TEI_ATTRIBUTE' in source_type:
            # Check if linked object is present
            if target_var.get('dataElement') or target_var.get('trackedEntityAttribute'):
                score += 10
                variable_linked = True
                feedback_parts.append("Variable source linked (+10)")
            else:
                feedback_parts.append("Variable source type set but no element selected")
        else:
            feedback_parts.append(f"Variable source type incorrect: {source_type}")
            
    # 2. Check Rules
    # We look for two distinct rules based on keywords
    rule1_found = False # Out of range
    rule2_found = False # Low birth weight
    
    rule1_obj = None
    rule2_obj = None
    
    for r in new_rules:
        name = r.get('name', '').lower()
        
        # Rule 1 detection
        if ('range' in name or 'limit' in name or 'out' in name) and not rule1_found:
            rule1_found = True
            rule1_obj = r
            continue
            
        # Rule 2 detection
        if ('low' in name or 'birth' in name or 'lbw' in name) and not rule2_found:
            rule2_found = True
            rule2_obj = r
            continue
            
    # Fallback: if we have rules but names didn't match perfectly, assign sequentially
    remaining_rules = [r for r in new_rules if r != rule1_obj and r != rule2_obj]
    if not rule1_found and remaining_rules:
        rule1_found = True
        rule1_obj = remaining_rules.pop(0)
        feedback_parts.append("Found a rule (assumed 'Out of Range')")
    if not rule2_found and remaining_rules:
        rule2_found = True
        rule2_obj = remaining_rules.pop(0)
        feedback_parts.append("Found second rule (assumed 'Low Birth Weight')")

    # Score Rule 1
    if rule1_found:
        score += 20
        feedback_parts.append("Rule #1 created (+20)")
        
        # Check condition
        cond = rule1_obj.get('condition', '')
        if cond and ('< ' in cond or '> ' in cond or '&' in cond or '|' in cond) and '#{' in cond:
            score += 10
            feedback_parts.append("Rule #1 condition valid (+10)")
        else:
            feedback_parts.append(f"Rule #1 condition issue: '{cond}'")
            
        # Check action
        actions = rule1_obj.get('programRuleActions', [])
        has_warning = any(a.get('programRuleActionType') in ['SHOWWARNING', 'SHOWERROR'] for a in actions)
        if has_warning:
            score += 10
            feedback_parts.append("Rule #1 action valid (+10)")
        else:
            feedback_parts.append("Rule #1 missing warning action")
    else:
        feedback_parts.append("Rule #1 (Range) not found")

    # Score Rule 2
    if rule2_found:
        score += 15
        feedback_parts.append("Rule #2 created (+15)")
        
        # Check condition
        cond = rule2_obj.get('condition', '')
        if cond and ('<' in cond or '>' in cond) and '#{' in cond:
            score += 5
            feedback_parts.append("Rule #2 condition valid (+5)")
            
        # Check action
        actions = rule2_obj.get('programRuleActions', [])
        has_warning = any(a.get('programRuleActionType') in ['SHOWWARNING', 'SHOWERROR'] for a in actions)
        if has_warning:
            score += 5
            feedback_parts.append("Rule #2 action valid (+5)")
    else:
        feedback_parts.append("Rule #2 (Low BW) not found")

    # Programme Association (Implicitly checked by API filter, but give points if rules exist)
    if rule1_found or rule2_found:
        score += 10
        feedback_parts.append("Rules associated with Child Programme (+10)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }