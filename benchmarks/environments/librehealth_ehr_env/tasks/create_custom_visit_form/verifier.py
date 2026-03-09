#!/usr/bin/env python3
"""
Verifier for create_custom_visit_form task.

Verifies that:
1. A form with ID 'LBF_Neuro' exists in layout_options.
2. It has a group named 'Reflexes'.
3. It has fields 'Patellar Reflex' and 'Achilles Reflex'.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_visit_form(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    layout_rows = result.get('layout_rows', [])
    
    score = 0
    feedback = []
    
    # Analyze the rows
    form_found = False
    group_found = False
    patellar_found = False
    achilles_found = False
    
    # Metadata expectations
    expected_form_id = "LBF_Neuro"
    
    for row in layout_rows:
        f_id = row.get('form_id', '')
        title = row.get('title', '')
        # data_type = row.get('data_type', '') 
        
        # Check for Form existence
        # In LBF, often the entries share the form_id
        if f_id == expected_form_id:
            form_found = True
        
        # Check for Group
        # Groups in LBF often have a specific structure, but checking title is usually sufficient for LBF editor tasks
        if "Reflexes" in title:
            group_found = True
            
        # Check for Fields
        if "Patellar Reflex" in title:
            patellar_found = True
        if "Achilles Reflex" in title:
            achilles_found = True

    # Scoring
    if form_found:
        score += 30
        feedback.append("Form 'LBF_Neuro' created.")
    else:
        feedback.append("Form 'LBF_Neuro' NOT found in database.")

    if group_found:
        score += 20
        feedback.append("Group 'Reflexes' found.")
    else:
        feedback.append("Group 'Reflexes' NOT found.")

    if patellar_found:
        score += 20
        feedback.append("Field 'Patellar Reflex' found.")
    else:
        feedback.append("Field 'Patellar Reflex' NOT found.")

    if achilles_found:
        score += 20
        feedback.append("Field 'Achilles Reflex' found.")
    else:
        feedback.append("Field 'Achilles Reflex' NOT found.")

    # Check for enable status (implicit if rows exist in layout_options usually means enabled/created)
    # We'll give the final 10 points if the basic structure is there
    if form_found and group_found and (patellar_found or achilles_found):
        score += 10
        feedback.append("Form structure appears valid.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }