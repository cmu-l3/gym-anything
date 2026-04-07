#!/usr/bin/env python3
"""
Verifier for create_subproject@1 task.

Checks that a sub-project was correctly created under DevOps Automation
with the expected name, identifier, description, parent, and modules.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_subproject(traj, env_info, task_info):
    """
    Verify the creation of the 'CI/CD Pipeline Hardening' sub-project.
    
    Scoring Criteria:
    1. Project exists (20 pts)
    2. Name matches exactly (15 pts)
    3. Parent is 'DevOps Automation' (25 pts) - CRITICAL
    4. Description contains key phrases (15 pts)
    5. Work package tracking module enabled (10 pts)
    6. Wiki module enabled (10 pts)
    7. Anti-gaming: Created after task start (5 pts)
    
    Pass Threshold: 70 points AND correct parent relationship.
    """
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "CI/CD Pipeline Hardening")
    expected_identifier = metadata.get('expected_identifier', "cicd-pipeline-hardening")
    expected_parent = metadata.get('expected_parent_identifier', "devops-automation")
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Extract Data
    project_data = result.get('project_data', {})
    found = project_data.get('found', False)
    task_start = int(result.get('task_start', 0))
    
    score = 0
    feedback_parts = []
    
    # CHECK 1: Project Exists (20 pts)
    if not found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Project with identifier '{expected_identifier}' was not found. The agent failed to create the project."
        }
    
    score += 20
    feedback_parts.append(f"[+20] Project '{expected_identifier}' exists")
    
    # CHECK 2: Name Match (15 pts)
    actual_name = project_data.get('name', '').strip()
    if actual_name == expected_name:
        score += 15
        feedback_parts.append(f"[+15] Name matches: '{actual_name}'")
    else:
        feedback_parts.append(f"[+0] Name mismatch. Expected '{expected_name}', got '{actual_name}'")
        
    # CHECK 3: Parent Relationship (25 pts) - CRITICAL
    actual_parent = project_data.get('parent_identifier', '')
    parent_correct = False
    if actual_parent == expected_parent:
        score += 25
        feedback_parts.append(f"[+25] Parent project is correctly set to '{actual_parent}'")
        parent_correct = True
    else:
        feedback_parts.append(f"[+0] Parent project mismatch. Expected '{expected_parent}', got '{actual_parent}'")
        
    # CHECK 4: Description Content (15 pts)
    actual_desc = project_data.get('description', '').lower()
    keywords = metadata.get('expected_description_keywords', ["reliability", "security", "rollback"])
    found_keywords = [kw for kw in keywords if kw in actual_desc]
    
    if len(found_keywords) >= 2:
        score += 15
        feedback_parts.append(f"[+15] Description contains {len(found_keywords)}/{len(keywords)} required keywords")
    elif len(found_keywords) == 1:
        score += 7
        feedback_parts.append(f"[+7] Description contains only 1 keyword ({found_keywords[0]})")
    else:
        # Check if description is at least substantial
        if len(actual_desc) > 20:
            score += 3
            feedback_parts.append("[+3] Description is present but missing keywords")
        else:
            feedback_parts.append("[+0] Description missing or too short")

    # CHECK 5 & 6: Modules (20 pts total)
    enabled_modules = [m.lower().replace('_', ' ') for m in project_data.get('enabled_modules', [])]
    
    # Work package tracking
    if "work package tracking" in enabled_modules:
        score += 10
        feedback_parts.append("[+10] 'Work package tracking' module enabled")
    else:
        feedback_parts.append("[+0] 'Work package tracking' module missing")
        
    # Wiki
    if "wiki" in enabled_modules:
        score += 10
        feedback_parts.append("[+10] 'Wiki' module enabled")
    else:
        feedback_parts.append("[+0] 'Wiki' module missing")

    # CHECK 7: Anti-Gaming Timestamp (5 pts)
    created_at = int(project_data.get('created_at_epoch', 0))
    if created_at >= task_start:
        score += 5
        feedback_parts.append("[+5] Project created during task session")
    else:
        feedback_parts.append(f"[+0] ANTI-GAMING: Project creation time ({created_at}) is before task start ({task_start})")
        
    # 3. Final Determination
    passed = (score >= 70) and parent_correct
    
    final_feedback = f"Final Score: {score}/100\n" + "\n".join(feedback_parts)
    if not parent_correct:
        final_feedback += "\n\nFAIL: The project was not created as a sub-project of 'DevOps Automation'."
        
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }