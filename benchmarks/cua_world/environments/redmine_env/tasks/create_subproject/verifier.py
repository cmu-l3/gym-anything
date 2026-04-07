#!/usr/bin/env python3
"""
Verifier for create_subproject task.

Verifies:
1. Sub-project exists with correct identifier (25 pts)
2. Parent project is correct (20 pts)
3. Description contains required keywords (15 pts)
4. Privacy setting is Private (15 pts)
5. Enabled modules match requirements exactly (25 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_subproject(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Checks
    if not result.get('project_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Project 'electrical-interconnection' was not found in Redmine."
        }

    project_data = result.get('project_data', {}).get('project', {})
    expected_parent_id = str(result.get('expected_parent_id', ''))
    
    score = 0
    feedback = []

    # 1. Project Exists (Base Score) - 25 pts
    score += 25
    feedback.append("Project created successfully.")

    # 2. Check Parent Project - 20 pts
    actual_parent = project_data.get('parent', {})
    actual_parent_id = str(actual_parent.get('id', ''))
    
    if actual_parent_id and actual_parent_id == expected_parent_id:
        score += 20
        feedback.append("Correct parent project selected.")
    else:
        feedback.append(f"Wrong parent project. Expected ID {expected_parent_id}, got {actual_parent_id}.")

    # 3. Check Description Keywords - 15 pts
    description = project_data.get('description', '').lower()
    keywords = ["interconnection", "utility", "compliance", "commissioning"]
    found_keywords = [k for k in keywords if k in description]
    
    if len(found_keywords) >= 3:
        score += 15
        feedback.append("Description contains required keywords.")
    elif len(found_keywords) >= 1:
        score += 5
        feedback.append("Description contains some keywords, but incomplete.")
    else:
        feedback.append("Description missing required context.")

    # 4. Check Privacy (is_public should be False) - 15 pts
    is_public = project_data.get('is_public', True) # Default to true if missing
    if is_public is False:
        score += 15
        feedback.append("Privacy set to Private correctly.")
    else:
        feedback.append("Project is Public (expected Private).")

    # 5. Check Modules - 25 pts
    # Expected: issue_tracking, time_tracking, gantt, calendar, wiki
    # Forbidden: news, documents, files, repository, boards
    enabled_modules = [m.get('name') for m in project_data.get('enabled_modules', [])]
    
    required = {"issue_tracking", "time_tracking", "gantt", "calendar", "wiki"}
    forbidden = {"news", "documents", "files", "repository", "boards"}
    
    actual_set = set(enabled_modules)
    
    missing_required = required - actual_set
    present_forbidden = forbidden.intersection(actual_set)
    
    if not missing_required and not present_forbidden:
        score += 25
        feedback.append("Modules configured exactly as requested.")
    else:
        # Partial scoring for modules
        module_score = 0
        # 3 points for each required module present (max 15)
        module_score += (len(required) - len(missing_required)) * 3
        # -2 points for each forbidden module present
        module_score -= len(present_forbidden) * 2
        
        # Clamp between 0 and 20 (max for partial is less than perfect 25)
        module_score = max(0, min(20, module_score))
        
        score += module_score
        feedback.append(f"Module configuration imperfect. Missing: {list(missing_required)}. Unexpected: {list(present_forbidden)}.")

    passed = score >= 60 and result.get('project_found')

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }