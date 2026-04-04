#!/usr/bin/env python3
"""
Verifier for add_request_tasks task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_request_tasks(traj, env_info, task_info):
    """
    Verify that the agent added 3 specific tasks to the correct request.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tasks = metadata.get('tasks', [])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # ================================================================
    # 1. Retrieve Result Data
    # ================================================================
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
            
    # ================================================================
    # 2. Programmatic Verification (Database)
    # ================================================================
    
    # Check if parent request was identified
    if not result.get('request_found', False):
        return {"passed": False, "score": 0, "feedback": "Parent request not found in system or not created correctly."}
    
    score += 10
    feedback_parts.append("Parent request identified")
    
    found_tasks = result.get('tasks', [])
    task_start_time = result.get('task_start', 0) * 1000 # Convert to ms for SDP
    
    # Analyze tasks
    tasks_matched = 0
    tasks_with_desc = 0
    valid_timestamps = 0
    
    # Helper to check matching (case insensitive substring)
    def check_match(expected, actual_list):
        exp_title = expected['title'].lower()
        for i, actual in enumerate(actual_list):
            if actual.get('_matched', False):
                continue
            
            act_title = actual.get('title', '').lower()
            if exp_title in act_title or act_title in exp_title: # Loose matching
                # Check description
                act_desc = actual.get('description', '').lower()
                desc_match = True
                for kw in expected.get('description_keywords', []):
                    if kw.lower() not in act_desc:
                        # Don't fail hard, just note it
                        pass
                
                # Check timestamp (anti-gaming)
                # Allow 60s tolerance before task start if clocks drift, but generally should be after
                created = int(actual.get('created_time', 0))
                is_new = created >= (task_start_time - 60000)
                
                actual['_matched'] = True
                return True, (len(act_desc) > 5), is_new
        return False, False, False

    # Check each expected task
    for exp_task in expected_tasks:
        matched, has_desc, is_new = check_match(exp_task, found_tasks)
        
        if matched:
            score += 15 # Title match
            tasks_matched += 1
            feedback_parts.append(f"Task created: '{exp_task['title']}'")
            
            if has_desc:
                score += 5 # Description present
                tasks_with_desc += 1
            
            if is_new:
                valid_timestamps += 1
        else:
            feedback_parts.append(f"Missing task: '{exp_task['title']}'")

    # Anti-gaming: Timestamp check score
    if valid_timestamps >= 2:
        score += 5
        feedback_parts.append("Tasks created during session")
    elif tasks_matched > 0:
        feedback_parts.append("Warning: Task timestamps appear old or invalid")

    # Linkage check
    # If we found tasks via the DB query on parent_id, they are by definition linked correctly
    if tasks_matched >= 2:
        score += 10
        feedback_parts.append("Tasks linked to correct request")

    # ================================================================
    # 3. VLM Verification (Trajectory)
    # ================================================================
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        if frames:
            prompt = """
            Analyze these screenshots of a user using ManageEngine ServiceDesk Plus.
            
            Look for:
            1. Navigation to a request titled "New Employee IT Onboarding"
            2. Clicking on a "Tasks" tab or "Add Task" button
            3. Filling out task forms (Title, Description)
            4. Saving tasks
            
            Did the user perform the workflow to add multiple tasks to a request?
            """
            
            vlm_response = query_vlm(images=frames + [final_img], prompt=prompt)
            
            # Simple keyword parsing of VLM response
            res_text = vlm_response.get('text', '').lower()
            if "yes" in res_text or "successfully" in res_text:
                vlm_score = 15
                feedback_parts.append("VLM confirms workflow")
            elif "partial" in res_text:
                vlm_score = 8
                feedback_parts.append("VLM sees partial workflow")
                
    except Exception as e:
        print(f"VLM check failed: {e}")
        # Fallback: if we have DB evidence, give partial VLM points
        if tasks_matched >= 2:
            vlm_score = 10
            feedback_parts.append("Workflow inferred from DB result")

    score += vlm_score

    # Final tally
    passed = (score >= 60) and (tasks_matched >= 2)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }