#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_project_tasks(traj, env_info, task_info):
    """
    Verify that the Project, Project Tasks, and Project Milestones 
    were correctly created and linked in Vtiger CRM.
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

    score = 0
    feedback_parts = []
    
    project_found = result.get("project_found", False)
    project = result.get("project", {})
    tasks = result.get("tasks", [])
    milestones = result.get("milestones", [])
    task_start = result.get("task_start", 0)
    
    if not project_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Project 'Riverside Office Park - Landscape Renovation' not found in database."
        }
        
    # Check anti-gaming
    created_time = project.get("createdtime", 0)
    if created_time > 0 and task_start > 0 and created_time < (task_start - 60):
        # Project was created before the task started
        return {
            "passed": False,
            "score": 0,
            "feedback": "Project existed before task started (Anti-gaming)."
        }

    # 1. Project exists -> 15 pts
    score += 15
    feedback_parts.append("Project created")
    
    metadata = task_info.get('metadata', {})
    
    # 2. Project dates (10 pts)
    start = project.get("startdate", "")
    end = project.get("targetenddate", "")
    exp_start = metadata.get("expected_start_date", "2025-02-01")
    exp_end = metadata.get("expected_end_date", "2025-04-30")
    if start == exp_start and end == exp_end:
        score += 10
        feedback_parts.append("Project dates correct")
    else:
        feedback_parts.append(f"Project dates mismatch: expected {exp_start} to {exp_end}, got {start} to {end}")
        
    # 3. Project status and priority (10 pts)
    status = project.get("projectstatus", "").lower()
    priority = project.get("projectpriority", "").lower()
    exp_status = metadata.get("expected_status", "in progress")
    exp_priority = metadata.get("expected_priority", "high")
    if status == exp_status and priority == exp_priority:
        score += 10
        feedback_parts.append("Project status/priority correct")
    else:
        feedback_parts.append("Project status/priority mismatch")
        
    # 4. Project description (5 pts)
    desc = project.get("description", "").lower()
    if "landscape renovation" in desc:
        score += 5
        feedback_parts.append("Project description present")
    else:
        feedback_parts.append("Project description missing or incorrect")
        
    # Process Tasks
    exp_tasks = metadata.get("expected_tasks", [])
    task_accurate_count = 0
    
    def evaluate_task(exp_t, tasks_list):
        for t in tasks_list:
            if exp_t["name"].lower() in t.get("projecttaskname", "").lower():
                # Found it, evaluate field accuracy
                acc = 0
                if t.get("startdate") == exp_t["start"]: acc += 1
                if t.get("enddate") == exp_t["end"]: acc += 1
                if t.get("projecttaskpriority", "").lower() == exp_t["priority"].lower(): acc += 1
                
                # Progress safely matched
                prog_val = t.get("projecttaskprogress", "").replace("%", "").strip()
                if prog_val.endswith(".0"): prog_val = prog_val[:-2] # e.g. 100.0 to 100
                if exp_t["progress"] == prog_val: acc += 1
                
                return True, acc >= 3
        return False, False

    # Evaluate Task 1
    found, acc = evaluate_task(exp_tasks[0], tasks)
    if found:
        score += 10
        feedback_parts.append("Task 1 linked")
        if acc: task_accurate_count += 1
    
    # Evaluate Task 2
    found, acc = evaluate_task(exp_tasks[1], tasks)
    if found:
        score += 10
        feedback_parts.append("Task 2 linked")
        if acc: task_accurate_count += 1
        
    # Evaluate Task 3
    found, acc = evaluate_task(exp_tasks[2], tasks)
    if found:
        score += 10
        feedback_parts.append("Task 3 linked")
        if acc: task_accurate_count += 1
        
    # Task field accuracy (10 pts if at least 2 are generally accurate)
    if task_accurate_count >= 2:
        score += 10
        feedback_parts.append("Task fields accurate")
        
    # Process Milestones
    exp_milestones = metadata.get("expected_milestones", [])
    
    def evaluate_milestone(exp_m, milestones_list):
        for m in milestones_list:
            if exp_m["name"].lower() in m.get("projectmilestonename", "").lower():
                if m.get("projectmilestonedate") == exp_m["date"]:
                    return True
        return False

    # Evaluate Milestone 1
    if len(exp_milestones) > 0 and evaluate_milestone(exp_milestones[0], milestones):
        score += 10
        feedback_parts.append("Milestone 1 linked and accurate")
        
    # Evaluate Milestone 2
    if len(exp_milestones) > 1 and evaluate_milestone(exp_milestones[1], milestones):
        score += 10
        feedback_parts.append("Milestone 2 linked and accurate")
        
    # Pass Threshold: 60 points
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }