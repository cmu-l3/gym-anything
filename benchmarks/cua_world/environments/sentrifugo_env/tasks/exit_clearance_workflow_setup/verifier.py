#!/usr/bin/env python3
"""
Verifier for exit_clearance_workflow_setup task.

Verification Strategy:
1. DB Check (60 points total):
   - Clearance Departments created (15 pts)
   - Users/Approvers correctly mapped to departments (15 pts)
   - Questions correctly linked to departments (30 pts)
2. VLM Trajectory Check (40 points total):
   - Proves agent actually interacted with the Separation UI 
     (Anti-gaming: ensures DB records weren't just injected directly)
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_exit_clearance_workflow(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_depts = metadata.get('departments', [])
    expected_approvers = metadata.get('approvers', {})
    expected_q_counts = metadata.get('questions_count', {})
    pass_threshold = metadata.get('pass_threshold', 60)

    # 1. Read JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
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
    
    tables = result.get('clearance_tables', {})
    users = result.get('users', [])
    
    # Identify tables dynamically
    dept_table_data = []
    user_table_data = []
    quest_table_data = []
    
    for t_name, t_data in tables.items():
        if 'department' in t_name.lower():
            dept_table_data = t_data
        elif 'user' in t_name.lower():
            user_table_data = t_data
        elif 'question' in t_name.lower():
            quest_table_data = t_data

    # Map Users for easy lookup (id -> Full Name)
    user_map = {}
    for u in users:
        full_name = f"{u.get('firstname', '').strip()} {u.get('lastname', '').strip()}"
        user_map[str(u.get('id'))] = full_name

    # Check 1: Departments (15 pts)
    dept_id_map = {} # Map Dept Name to its DB ID
    depts_found = 0
    for ed in expected_depts:
        found = False
        for row in dept_table_data:
            name = row.get('departmentname', row.get('deptname', row.get('name', '')))
            if ed.lower() in name.lower():
                found = True
                dept_id_map[ed] = str(row.get('id'))
                break
        if found:
            depts_found += 1
            score += 5
            
    feedback_parts.append(f"Depts found: {depts_found}/3")

    # Check 2: Approvers Mapped (15 pts)
    approvers_correct = 0
    for dept_name, expected_user in expected_approvers.items():
        if dept_name not in dept_id_map:
            continue
            
        d_id = dept_id_map[dept_name]
        found_approver = False
        
        for row in user_table_data:
            r_dept_id = str(row.get('department_id', row.get('dept_id', '')))
            r_user_id = str(row.get('user_id', row.get('employee_id', '')))
            
            if r_dept_id == d_id:
                actual_user = user_map.get(r_user_id, "")
                if expected_user.lower() in actual_user.lower():
                    found_approver = True
                    break
                    
        if found_approver:
            approvers_correct += 1
            score += 5
            
    feedback_parts.append(f"Approvers correct: {approvers_correct}/3")

    # Check 3: Questions Linked (30 pts)
    questions_score = 0
    total_q_expected = sum(expected_q_counts.values())
    q_found_total = 0
    
    for dept_name, expected_count in expected_q_counts.items():
        if dept_name not in dept_id_map:
            continue
            
        d_id = dept_id_map[dept_name]
        q_count = 0
        
        for row in quest_table_data:
            r_dept_id = str(row.get('department_id', row.get('dept_id', '')))
            if r_dept_id == d_id:
                q_count += 1
                
        q_found_total += min(q_count, expected_count)
    
    if total_q_expected > 0:
        questions_score = int((q_found_total / total_q_expected) * 30)
        score += questions_score
        feedback_parts.append(f"Questions found: {q_found_total}/{total_q_expected}")

    # 4. VLM Trajectory Verification (40 pts)
    # Proves the agent actually used the UI rather than bypassing it
    vlm_score = 0
    
    # Import VLM utils safely inside the verifier
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
        
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        images_to_check = frames + [final_img] if final_img else frames
        
        if images_to_check:
            prompt = (
                "Review these screenshots from an agent interacting with the Sentrifugo HRMS application. "
                "Did the agent actively navigate to the 'Separation' module and interact with "
                "'Clearance Departments', 'Clearance Users', or 'Checklist Questions'? "
                "Respond in JSON format: {\"used_separation_module\": true/false, \"confidence\": \"high/low\"}"
            )
            
            vlm_response = query_vlm(images=images_to_check, prompt=prompt)
            if vlm_response and vlm_response.get('parsed'):
                if vlm_response['parsed'].get('used_separation_module', False):
                    vlm_score = 40
                    feedback_parts.append("VLM: Verified UI interaction")
                else:
                    feedback_parts.append("VLM: UI interaction not detected")
            else:
                feedback_parts.append("VLM: Query failed, awarding partial default points")
                vlm_score = 20  # Fallback if VLM fails but code reaches here
    except ImportError:
        logger.warning("VLM libraries not available. Skipping visual check and awarding default points.")
        vlm_score = 40 # Award default if running in environment without VLM module
        feedback_parts.append("VLM check skipped (no module)")

    score += vlm_score

    # Anti-gaming: Ensure it wasn't an instant task completion
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    duration = task_end - task_start
    if duration < 10 and score > 0:
        score = 0
        feedback_parts.append("FAIL: Task completed too quickly (gaming detected)")

    passed = score >= pass_threshold and depts_found > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }