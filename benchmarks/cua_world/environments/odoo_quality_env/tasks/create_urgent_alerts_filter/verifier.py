#!/usr/bin/env python3
"""
Verifier for create_urgent_alerts_filter task.

Verifies:
1. A custom filter named 'Urgent Actions' exists in Odoo.
2. The filter domain correctly targets 'High Priority' (priority > 0 or = 1).
3. The filter domain correctly targets 'New' Stage.
4. The filter was created during the task session.
"""

import json
import tempfile
import os
import logging
import ast

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_urgent_alerts_filter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Filter Existence (30 pts)
    if not result.get('filter_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No filter named 'Urgent Actions' found in Quality Alerts."
        }
    
    score += 30
    feedback_parts.append("Filter 'Urgent Actions' created.")
    
    # 2. Analyze Domain Logic
    domain_str = result.get('filter_domain', '[]')
    new_stage_ids = result.get('stage_new_id', [])
    
    try:
        domain = ast.literal_eval(domain_str)
        
        has_priority_check = False
        has_stage_check = False
        
        # Odoo domains are lists of tuples: [('field', 'operator', 'value'), ...]
        # They can also be Polish notation with operators like '&', '|'
        
        for item in domain:
            if isinstance(item, (list, tuple)) and len(item) == 3:
                field, op, val = item
                
                # Check Priority
                # Priority in Odoo 17 Quality is usually '0' (Normal) or '1' (High)
                # Valid logic: priority = '1' OR priority > '0' OR priority != '0'
                if field == 'priority':
                    val_str = str(val)
                    if (op == '=' and val_str in ['1', '2', '3']) or \
                       (op in ['>', '!='] and val_str == '0'):
                        has_priority_check = True
                
                # Check Stage
                # Valid logic: stage_id = <ID of New> OR stage_id.name ilike 'New'
                if field == 'stage_id':
                    if op in ['=', 'in']:
                        # Check if value matches one of the known "New" stage IDs
                        if isinstance(val, int) and val in new_stage_ids:
                            has_stage_check = True
                        elif isinstance(val, list) and any(v in new_stage_ids for v in val):
                            has_stage_check = True
                elif field == 'stage_id.name':
                     if 'new' in str(val).lower():
                         has_stage_check = True
        
        # Score Logic
        if has_priority_check:
            score += 25
            feedback_parts.append("Priority condition correct (High).")
        else:
            feedback_parts.append("Priority condition missing or incorrect.")

        if has_stage_check:
            score += 25
            feedback_parts.append("Stage condition correct (New).")
        else:
            feedback_parts.append("Stage condition missing or incorrect.")
            
        # 3. Combined Logic (Implicit AND)
        # If both checks are present in the list, Odoo defaults to AND
        if has_priority_check and has_stage_check:
            score += 10
            feedback_parts.append("Conditions combined successfully.")

    except Exception as e:
        feedback_parts.append(f"Error parsing domain: {e}")

    # 4. Anti-gaming / Timestamp (10 pts)
    # We verified existence and logic; if it exists, it was created during task 
    # (since setup cleared old ones).
    if result.get('created_after_start'):
        score += 10
        feedback_parts.append("Filter created during task session.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }