#!/usr/bin/env python3
"""
Verifier for create_privilege task in Bahmni/OpenMRS.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_privilege(traj, env_info, task_info):
    """
    Verify that the privilege was created correctly in OpenMRS.
    
    Criteria:
    1. Privilege 'View Triage Queue' exists (60 pts)
    2. Description contains 'triage' and 'queue' (30 pts)
    3. Anti-gaming: Privilege did not exist at start (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Copy result from container
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
            
    score = 0
    feedback_parts = []
    
    # Check 1: Privilege exists (60 pts)
    exists = result.get('privilege_exists', False)
    if exists:
        score += 60
        feedback_parts.append("Privilege created successfully")
    else:
        feedback_parts.append("Privilege 'View Triage Queue' NOT found")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }

    # Check 2: Description content (30 pts)
    description = result.get('privilege_description', '').lower()
    keywords = task_info.get('metadata', {}).get('expected_description_keywords', ['triage', 'queue'])
    
    missing_keywords = [k for k in keywords if k not in description]
    
    if not missing_keywords:
        score += 30
        feedback_parts.append("Description correct")
    elif len(missing_keywords) < len(keywords):
        score += 15
        feedback_parts.append(f"Description partial match (missing: {', '.join(missing_keywords)})")
    else:
        feedback_parts.append("Description missing required keywords")
        
    # Check 3: Anti-gaming (10 pts)
    # Ensure it wasn't there before (setup script cleans it up, so this verifies setup ran and agent did work)
    initial_exists = result.get('initial_exists', False)
    if not initial_exists:
        score += 10
        feedback_parts.append("Valid creation (not pre-existing)")
    else:
        feedback_parts.append("Warning: Privilege existed at start")
        
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }