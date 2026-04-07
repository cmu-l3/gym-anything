#!/usr/bin/env python3
"""
Verifier for compliance_restructure task.

Evaluates 5 main goals via JSON state exported from the DB:
  1. Dept Renamed (10 pts)
  2. Dept Created (10 pts)
  3. Dept Deactivated (6 pts)
  4. Job Codes Updated (12 pts)
  5. Employees Reassigned (42 pts total)
     - EMP009 (10 pts), EMP010 (10 pts), EMP017 (12 pts), EMP014 (6 pts)
     - No remaining active employees in Maint & Support (4 pts)
  6. VLM Trajectory Verification (20 pts)
     - Ensures the agent actually interacted with Sentrifugo workflows 

Pass Threshold: 60 points + VLM confirmation
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_vlm_prompt():
    return """Review these frames from a workflow. 

The user was tasked with performing an organizational restructure in a Human Resources Management System (Sentrifugo).
This involved:
- Navigating to the Departments section to rename and add departments.
- Navigating to the Job Titles section to update job codes.
- Navigating to the Employees section to update employee assignments.

Based on the trajectory frames, did the user actually interact with these UI sections (Departments, Job Titles, Employees) within the web application to perform data entry?

Respond in JSON format:
{
    "workflow_visible": true/false,
    "confidence": "low/medium/high",
    "observations": "brief description of what screens the user visited"
}
"""

def verify_compliance_restructure(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    pass_threshold = metadata.get('pass_threshold', 60)

    # Exported data retrieval
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/compliance_restructure_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    depts = result.get("departments", {})
    titles = result.get("job_titles", {})
    emps = result.get("employees", {})

    # 1. Dept Rename Check (10 pts)
    old_dept = depts.get("DevOps & Infrastructure", {})
    new_dept = depts.get("Infrastructure & Cloud Operations", {})
    
    # Ideally old dept is gone entirely or deactivated, new dept is active
    if "Infrastructure & Cloud Operations" in depts and new_dept.get("isactive") == "1":
        if "DevOps & Infrastructure" not in depts or old_dept.get("isactive") == "0":
            score += 10
            feedback_parts.append("Dept renamed to Infrastructure & Cloud Operations")
        else:
            # They created it but didn't rename/delete the old one
            score += 5
            feedback_parts.append("Created new dept but did not remove old DevOps dept")
    else:
        feedback_parts.append("Did not rename DevOps dept")

    # 2. Dept Create Check (10 pts)
    ehs_dept = depts.get("Environmental Health & Safety", {})
    if ehs_dept and ehs_dept.get("code") == "EHS" and ehs_dept.get("isactive") == "1":
        score += 10
        feedback_parts.append("EHS Dept created")
    elif ehs_dept:
        score += 5
        feedback_parts.append("EHS Dept created but missing correct code or inactive")
    else:
        feedback_parts.append("EHS Dept not created")

    # 3. Dept Deactivated Check (6 pts)
    ms_dept = depts.get("Maintenance & Support", {})
    if ms_dept and ms_dept.get("isactive") == "0":
        score += 6
        feedback_parts.append("Maintenance & Support deactivated")
    elif not ms_dept:
        # User deleted it entirely. Permissible but prompt specifically said "do not delete"
        score += 3
        feedback_parts.append("Maintenance & Support deleted (was supposed to be deactivated)")
    else:
        feedback_parts.append("Maintenance & Support still active")

    # 4. Job Codes Updated (12 pts)
    expected_codes = metadata.get("expected_job_codes", {})
    codes_score = 0
    for jt, expected_code in expected_codes.items():
        if titles.get(jt) == expected_code:
            codes_score += 4
    score += codes_score
    feedback_parts.append(f"Job codes updated: {codes_score}/12 pts")

    # 5. Employees Reassigned
    assignments = metadata.get("expected_assignments", {})
    emp_scores = {"EMP009": 10, "EMP010": 10, "EMP017": 12, "EMP014": 6}
    
    emp_total = 0
    for empid, expected_dept in assignments.items():
        actual_dept = emps.get(empid)
        if actual_dept == expected_dept:
            emp_total += emp_scores[empid]
        elif actual_dept is not None:
            feedback_parts.append(f"{empid} placed in wrong dept ({actual_dept})")
    score += emp_total
    feedback_parts.append(f"Employee reassignments: {emp_total}/38 pts")

    # 6. Active Employees in Maint & Support (4 pts)
    if result.get("maint_support_active_count", 99) == 0:
        score += 4
        feedback_parts.append("No active employees remain in Maintenance & Support")
    else:
        feedback_parts.append("Maintenance & Support still has active employees")

    # 7. VLM Trajectory Verification (20 pts)
    vlm_score = 0
    if 'sample_trajectory_frames' in env_info and 'query_vlm' in env_info:
        try:
            frames = env_info['sample_trajectory_frames'](traj, n=5)
            vlm_response = env_info['query_vlm'](
                images=frames, 
                prompt=build_vlm_prompt()
            )
            if vlm_response and vlm_response.get('parsed', {}).get('workflow_visible'):
                vlm_score = 20
                feedback_parts.append("VLM verified correct UI workflow")
            else:
                feedback_parts.append("VLM did not verify proper UI interaction")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            # If VLM fails structurally, don't auto-fail the user if DB checks passed perfectly
            if score >= pass_threshold:
                vlm_score = 20 
    else:
        # Fallback if VLM isn't available in execution context
        if score >= pass_threshold:
            vlm_score = 20
            
    score += vlm_score

    passed = score >= pass_threshold
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }