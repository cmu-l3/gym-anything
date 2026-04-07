#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_define_opportunity_buying_center(traj, env_info, task_info):
    """
    Verify the opportunity buying center task.
    Checks that the exactly required contacts are linked to the opportunity 
    with the exact specified roles.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    task_start = result.get('task_start', 0)
    relationships = result.get('relationships', [])

    score = 0
    feedback_parts = []
    
    # Define expected names and roles
    expected_roles = {
        ("Eleanor", "Vance"): "Executive Sponsor",
        ("Marcus", "Thorne"): "Primary Decision Maker",
        ("David", "Chen"): "Technical Evaluator"
    }
    
    found_contacts = set()
    correct_roles = 0
    
    if not relationships:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No contacts linked to the opportunity."
        }
        
    for rel in relationships:
        fname = rel.get('first_name', '')
        lname = rel.get('last_name', '')
        role = rel.get('role', '')
        mtime = rel.get('mtime', 0)
        
        name_tuple = (fname, lname)
        found_contacts.add(name_tuple)
        
        if name_tuple in expected_roles:
            score += 10  # Base points for linking the correct person
            feedback_parts.append(f"Linked {fname} {lname}.")
            
            # Check if role matches (case-insensitive for robustness)
            if role.lower() == expected_roles[name_tuple].lower():
                score += 20
                correct_roles += 1
                feedback_parts.append(f"Role for {fname} {lname} is correct ({role}).")
            else:
                feedback_parts.append(f"Role for {fname} {lname} incorrect (Expected: '{expected_roles[name_tuple]}', Got: '{role}').")
                
        else:
            feedback_parts.append(f"Unexpected contact linked: {fname} {lname}.")
            
    # Clean State check - exactly 3 relationships, and no unexpected ones
    if len(relationships) == 3 and found_contacts == set(expected_roles.keys()):
        score += 10
        feedback_parts.append("Clean state maintained (exactly 3 contacts linked).")
    elif len(relationships) != 3:
        feedback_parts.append(f"Expected 3 total contacts linked, found {len(relationships)}.")

    # Requirements for pass: at least all 3 linked (10+10+10) and 2 out of 3 roles correct (20+20) + optionally clean state (10)
    # Total possible is 100. Pass threshold is 70 points.
    passed = score >= 70 and len(found_contacts) == 3 and correct_roles >= 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }