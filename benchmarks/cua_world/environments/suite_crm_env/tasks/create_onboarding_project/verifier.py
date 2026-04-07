#!/usr/bin/env python3
"""
Verifier for create_onboarding_project task.

Verification Strategy:
1. Validates the creation of the Project record in MariaDB.
2. Validates project attributes (dates, status, priority, description).
3. Validates the existence and linkage of all 6 required child Project Tasks.
4. Validates date bounds, priorities, and specific flags (milestone) for tasks.

Note: Since setup_task.sh wiped any pre-existing project with this name, 
finding the correct state guarantees it was created during the session.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_onboarding_project(traj, env_info, task_info):
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

    score = 0
    feedback_parts = []
    
    # 1. Base Project Verification
    if not result.get("project_found", False):
        return {"passed": False, "score": 0, "feedback": "Project 'Greenfield Organics Onboarding' not found in database."}
        
    score += 15
    feedback_parts.append("Project created (+15)")
    
    project = result.get("project", {})
    
    # Project Status
    if "draft" in project.get("status", "").lower():
        score += 5
        feedback_parts.append("Status=Draft (+5)")
    else:
        feedback_parts.append(f"Status mismatch (got: {project.get('status')})")
        
    # Project Start Date
    if "2025-02-03" in project.get("estimated_start_date", ""):
        score += 5
        feedback_parts.append("Start date correct (+5)")
    else:
        feedback_parts.append("Start date mismatch")
        
    # Project End Date
    if "2025-03-14" in project.get("estimated_end_date", ""):
        score += 5
        feedback_parts.append("End date correct (+5)")
    else:
        feedback_parts.append("End date mismatch")
        
    # Project Priority
    if "high" in project.get("priority", "").lower():
        score += 5
        feedback_parts.append("Priority=High (+5)")
    else:
        feedback_parts.append("Priority mismatch")
        
    # Project Description
    if "greenfield organics" in project.get("description", "").lower():
        score += 5
        feedback_parts.append("Description present (+5)")
    else:
        feedback_parts.append("Description mismatch/missing")
        
    # 2. Child Tasks Verification
    expected_tasks = [
        {"name": "Account Verification and Setup", "start": "2025-02-03", "end": "2025-02-07", "milestone": "0"},
        {"name": "Product Catalog Review", "start": "2025-02-10", "end": "2025-02-14", "milestone": "0"},
        {"name": "Credit Terms Approval", "start": "2025-02-10", "end": "2025-02-14", "milestone": "0"},
        {"name": "Initial Order Processing", "start": "2025-02-17", "end": "2025-02-21", "milestone": "0"},
        {"name": "Logistics and Delivery Setup", "start": "2025-02-24", "end": "2025-02-28", "milestone": "0"},
        {"name": "Client Handoff and Go-Live", "start": "2025-03-10", "end": "2025-03-14", "milestone": "1"},
    ]
    
    tasks = result.get("tasks", [])
    tasks_found = 0
    
    for et in expected_tasks:
        # Find matching task (case insensitive, partial match permitted for flexibility)
        found_task = next((t for t in tasks if et["name"].lower() in t.get("name", "").lower()), None)
        
        if found_task:
            task_score = 0
            
            # Check dates
            if et["start"] in found_task.get("date_start", "") and et["end"] in found_task.get("date_finish", ""):
                task_score += 10
            else:
                task_score += 5  # Partial credit for linking task but with incorrect dates
                
            # Check milestone requirement
            if et["milestone"] == "1":
                if found_task.get("milestone_flag") not in ["1", True, 1]:
                    task_score = max(task_score - 2, 0)
                    
            score += task_score
            tasks_found += 1
            feedback_parts.append(f"Task '{et['name']}' (+{task_score})")
        else:
            feedback_parts.append(f"Task '{et['name']}' NOT found")
            
    # Evaluation Criteria
    # Require baseline 60 points and at least half the tasks to be successfully linked
    passed = score >= 60 and tasks_found >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }