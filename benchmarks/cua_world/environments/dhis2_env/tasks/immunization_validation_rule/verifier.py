#!/usr/bin/env python3
"""
Verifier for immunization_validation_rule task.

Scoring (100 points total):
- Validation rule created (25 pts) [MANDATORY]
- Rule name references Penta/Immunization (10 pts)
- Rule has correct operator (>=) and side logic (10 pts)
- Rule references data elements (10 pts)
- Validation rule group created (15 pts)
- Rule group contains the new rule (5 pts)
- Results file exists and non-empty (15 pts)
- Results file has substantive content (10 pts)

Pass threshold: 60 points
Mandatory: Validation rule created
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_immunization_validation_rule(traj, env_info, task_info):
    """Verify creation of validation rule, group, and execution results."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/immunization_validation_rule_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        score = 0
        feedback_parts = []
        subscores = {}

        # Parse Data
        rules_data = result.get('rules_data', {})
        groups_data = result.get('groups_data', {})
        file_info = result.get('file_info', {})

        penta_rules = rules_data.get('penta_rules', [])
        relevant_groups = groups_data.get('relevant_groups', [])

        # Criterion 1: Rule Created (Mandatory)
        if not penta_rules:
            # Check if any rule was created even if name is wrong
            if rules_data.get('new_rules_count', 0) > 0:
                 feedback_parts.append("New validation rule created but name doesn't contain 'Penta'")
                 # Allow partial credit path if strict name check fails but logic might be right? 
                 # Task requirement says "Name the rule 'Penta1 >= Penta3'". 
                 # If they named it something else, we might miss it. 
                 # Let's stick to the filter from export_result.sh for simplicity.
                 return {
                    "passed": False, 
                    "score": 10, 
                    "feedback": "Created a rule, but name did not contain 'Penta' as required.",
                    "subscores": {"rule_created": True, "name_match": False}
                 }
            else:
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "No new validation rules found.",
                    "subscores": {"rule_created": False}
                }
        
        # Valid rule found
        score += 25
        subscores["rule_created"] = True
        target_rule = penta_rules[0] # Take the first match
        feedback_parts.append(f"Validation rule '{target_rule.get('displayName')}' created (+25)")

        # Criterion 2: Name Quality
        # Already filtered by 'penta' in export, giving full points if we are here
        score += 10
        subscores["name_match"] = True
        feedback_parts.append("Rule name contains 'Penta' (+10)")

        # Criterion 3: Operator Logic
        # Expected: greater_than_or_equal_to (Penta1 >= Penta3)
        operator = target_rule.get('operator', '')
        left_side = target_rule.get('leftSide', {}).get('description', '').lower()
        right_side = target_rule.get('rightSide', {}).get('description', '').lower()
        
        # We can't easily check the description if it's auto-generated or empty, 
        # but the operator is a strong signal.
        if operator == 'greater_than_or_equal_to':
            score += 10
            subscores["operator_logic"] = True
            feedback_parts.append("Operator 'greater_than_or_equal_to' is correct (+10)")
        elif operator == 'equal_to':
             # Maybe they did equal? Incorrect logic but partial points? No, logic is key.
             feedback_parts.append("Operator 'equal_to' is incorrect for this logic")
        else:
             feedback_parts.append(f"Operator '{operator}' found")

        # Criterion 4: Data Elements
        # Check if expressions contain IDs (basic check that it's not empty)
        left_expr = target_rule.get('leftSide', {}).get('expression', '')
        right_expr = target_rule.get('rightSide', {}).get('expression', '')
        
        if left_expr and right_expr and ('#' in left_expr or '{' in left_expr):
            score += 10
            subscores["data_elements"] = True
            feedback_parts.append("Rule expressions configured (+10)")
        else:
            feedback_parts.append("Rule expressions appear empty or invalid")

        # Criterion 5: Group Created
        if relevant_groups:
            score += 15
            subscores["group_created"] = True
            target_group = relevant_groups[0]
            feedback_parts.append(f"Validation group '{target_group.get('displayName')}' created (+15)")
            
            # Criterion 6: Group Membership
            # Check if the created rule ID is in the group
            rule_id = target_rule.get('id')
            group_rules = [r.get('id') for r in target_group.get('validationRules', [])]
            
            if rule_id in group_rules:
                score += 5
                subscores["group_membership"] = True
                feedback_parts.append("Rule added to group (+5)")
            else:
                feedback_parts.append("Rule NOT found in the new group")
        else:
            subscores["group_created"] = False
            feedback_parts.append("No immunization-related validation rule group found")

        # Criterion 7: Results File Exists
        if file_info.get('exists') and file_info.get('created_after_start'):
            score += 15
            subscores["file_exists"] = True
            feedback_parts.append("Results file created (+15)")
            
            # Criterion 8: File Content
            size = file_info.get('size', 0)
            content = file_info.get('content_snippet', '').lower()
            
            if size > 50 and any(w in content for w in ['violation', 'passed', 'unit', 'period', 'bo', 'penta']):
                score += 10
                subscores["file_content"] = True
                feedback_parts.append("Results file contains substantive content (+10)")
            else:
                feedback_parts.append("Results file content is minimal or generic")
        else:
            subscores["file_exists"] = False
            feedback_parts.append("Results file not found or not created during task")

        return {
            "passed": score >= 60,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}