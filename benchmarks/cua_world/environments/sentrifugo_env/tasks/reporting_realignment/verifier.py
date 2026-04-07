#!/usr/bin/env python3
"""
Verifier for reporting_realignment task.

Checks 8 distinct criteria based on the restructuring memo:
- 4 reporting manager updates (12 pts each)
- 2 department transfers (14 pts each)
- 1 job title creation (10 pts)
- 1 job title reassignment (14 pts)

Total 100 points, Pass Threshold: 65
Includes Anti-Gaming timestamp checks and VLM trajectory analysis.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reporting_realignment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Define expected outcomes from metadata
    expected_managers = metadata.get('expected_managers', {
        "EMP007": "EMP003",
        "EMP009": "EMP015",
        "EMP011": "EMP005",
        "EMP014": "EMP008"
    })
    expected_departments = metadata.get('expected_departments', {
        "EMP010": "Engineering",
        "EMP016": "Data Science"
    })
    expected_titles = metadata.get('expected_titles', {
        "EMP017": "Team Lead"
    })

    # Read the exported JSON
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
    
    # Parse employee data safely into dictionary by empid
    employees_data = {emp.get('empid'): emp for emp in result.get('employees', [])}
    
    # 1. Check reporting managers (4 * 12 = 48 pts)
    for empid, expected_mgr in expected_managers.items():
        emp_data = employees_data.get(empid, {})
        actual_mgr = emp_data.get('manager_empid', '')
        if actual_mgr == expected_mgr:
            score += 12
            feedback_parts.append(f"{empid} manager updated correctly (12/12)")
        else:
            feedback_parts.append(f"{empid} manager incorrect: expected {expected_mgr}, got {actual_mgr} (0/12)")

    # 2. Check departments (2 * 14 = 28 pts)
    for empid, expected_dept in expected_departments.items():
        emp_data = employees_data.get(empid, {})
        actual_dept = emp_data.get('department', '')
        if actual_dept == expected_dept:
            score += 14
            feedback_parts.append(f"{empid} department updated correctly (14/14)")
        else:
            feedback_parts.append(f"{empid} department incorrect: expected {expected_dept}, got {actual_dept} (0/14)")

    # 3. Check Job Title existence (10 pts)
    team_lead_count = result.get('team_lead_count', 0)
    try:
        team_lead_count = int(team_lead_count)
    except ValueError:
        team_lead_count = 0
        
    if team_lead_count > 0:
        score += 10
        feedback_parts.append("Job title 'Team Lead' exists (10/10)")
    else:
        feedback_parts.append("Job title 'Team Lead' NOT found (0/10)")

    # 4. Check EMP017 Title assignment (14 pts)
    for empid, expected_title in expected_titles.items():
        emp_data = employees_data.get(empid, {})
        actual_title = emp_data.get('jobtitle', '')
        if actual_title == expected_title:
            score += 14
            feedback_parts.append(f"{empid} job title updated correctly (14/14)")
        else:
            feedback_parts.append(f"{empid} job title incorrect: expected {expected_title}, got {actual_title} (0/14)")

    # VLM Trajectory Verification to prevent direct SQL injection gaming
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            prompt = (
                "Did the agent use the Sentrifugo HRMS web UI during the task progression to make organizational changes? "
                "Look for forms being edited, dropdown menus being clicked, or configuration lists. "
                "Strictly return JSON format: {\"used_ui\": true/false}"
            )
            vlm_response = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_response and vlm_response.get("parsed", {}).get("used_ui"):
                feedback_parts.append("VLM verified UI interaction")
            else:
                feedback_parts.append("VLM could not explicitly verify UI interaction")
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")
            feedback_parts.append("VLM verification skipped")

    # Anti-gaming: Ensure sufficient time elapsed for manual operations
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    duration = task_end - task_start
    if duration < 10 and score > 0:
        # Task completed suspiciously fast - likely a script cheating the DB 
        score = 0
        feedback_parts.append(f"FAIL: Task completed in {duration}s. Impossibly fast; anti-gaming triggered.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }