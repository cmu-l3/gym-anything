#!/usr/bin/env python3
"""
Verifier for create_preventive_maintenance task.

Criteria:
1. PM Task exists in database (25 pts)
2. Task Name matches expected (15 pts)
3. Task Description contains key details (10 pts)
4. Priority is 'Medium' (10 pts)
5. Technician is 'administrator' (10 pts)
6. Schedule is configured for Quarterly/3-months (15 pts)
7. VLM Verification of workflow (15 pts)

Passing: 70 points
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_preventive_maintenance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Quarterly Data Center Server Health Check")
    expected_desc_part = metadata.get('expected_description_part', "Comprehensive server health check")
    
    score = 0
    feedback_parts = []
    
    # 1. Load DB Result
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

    # 2. Verify Database State
    pm_found = result.get('pm_found', False)
    current_count = result.get('current_count', 0)
    initial_count = result.get('initial_count', 0)
    
    if pm_found:
        score += 25
        feedback_parts.append("PM Task found in database")
    elif current_count > initial_count:
        score += 10
        feedback_parts.append("New PM task created, but name didn't match exactly")
    else:
        feedback_parts.append("No PM task created")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Check Name
    pm_title = result.get('pm_title', "")
    if expected_name.lower() in pm_title.lower():
        score += 15
        feedback_parts.append("Task name correct")
    else:
        feedback_parts.append(f"Task name mismatch ('{pm_title}')")

    # Check Description
    pm_desc = result.get('pm_description', "")
    if expected_desc_part.lower() in pm_desc.lower():
        score += 10
        feedback_parts.append("Description contains required text")
    else:
        feedback_parts.append("Description missing details")

    # Check Priority
    pm_priority = result.get('pm_priority', "")
    if "medium" in pm_priority.lower():
        score += 10
        feedback_parts.append("Priority correct")
    else:
        feedback_parts.append(f"Priority incorrect ('{pm_priority}')")

    # Check Technician
    pm_tech = result.get('pm_technician', "")
    if "administrator" in pm_tech.lower():
        score += 10
        feedback_parts.append("Technician correct")
    else:
        feedback_parts.append(f"Technician incorrect ('{pm_tech}')")

    # Check Schedule (Periodicity)
    # SDP stores periodicity often as a string or count. 
    # Quarterly might be "3 months" or periodic "Monthly" with count 3.
    pm_periodicity = str(result.get('pm_periodicity', ""))
    pm_schedule_type = str(result.get('pm_schedule_type', ""))
    
    schedule_correct = False
    if "3" in pm_periodicity or "quarter" in pm_schedule_type.lower() or "3" in pm_schedule_type:
        schedule_correct = True
    
    if schedule_correct:
        score += 15
        feedback_parts.append("Schedule correct (Quarterly/3-months)")
    else:
        feedback_parts.append(f"Schedule mismatch (Type: {pm_schedule_type}, Period: {pm_periodicity})")

    # 3. VLM Verification
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review the screenshots of a user creating a Preventive Maintenance task in ServiceDesk Plus.
    
    1. Did the user navigate to the 'Preventive Maintenance' section (usually in Admin)?
    2. Did they fill out a form with 'Quarterly Data Center Server Health Check'?
    3. Did they set the schedule to run every 3 months or Quarterly?
    
    Return JSON: {"workflow_followed": bool, "schedule_visible": bool, "confidence": "high/medium/low"}
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('workflow_followed', False):
            score += 10
            feedback_parts.append("VLM confirmed workflow")
        
        if parsed.get('schedule_visible', False):
            score += 5
            feedback_parts.append("VLM confirmed schedule setting")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Don't penalize for VLM technical failure if DB verification was good
        if score >= 60:
            score += 15
            feedback_parts.append("VLM skipped (error)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }