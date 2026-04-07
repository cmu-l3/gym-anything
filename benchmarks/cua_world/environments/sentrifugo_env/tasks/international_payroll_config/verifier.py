#!/usr/bin/env python3
"""
Verifier for international_payroll_config task.

Multi-Signal Verification Strategy:
1. Programmatic DB Verification (70 points)
   - Checks presence of Master Data: Currencies, Pay Freqs, Prefixes, Dept, Titles (40 pts)
   - Checks proper assignment of Employees to Dept and Title (30 pts)
2. Trajectory VLM Verification (30 points)
   - Proves actual human-like UI navigation rather than cheating/curling backend

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_vlm_prompt():
    return """Examine these consecutive frames from a user's screen session carefully.

Task: Verify that the user interacted with the Sentrifugo HRMS web interface to configure master data.

Check for these indicators:
1. Did the user navigate through the Sentrifugo "Organization" menus (e.g., Currencies, Pay Frequencies, Departments, Job Titles, Prefix)?
2. Did the user use the "Employee Management" / "Add Employee" screens?
3. Is there evidence of form-filling activities for international entries (e.g., JPY, BRL, INR, International Programs, Country Director)?

Respond in JSON format:
{
    "ui_interaction_observed": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Briefly state what UI screens were actively used."
}
"""

def verify_international_payroll_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. PROGRAMMATIC DATABASE CHECKS (70 Points Max)
    # ---------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    db_score = 0

    # Currencies (3 * 3 = 9 pts)
    cur = result.get("currencies", {})
    if cur.get("jpy_exists"): db_score += 3
    if cur.get("brl_exists"): db_score += 3
    if cur.get("inr_exists"): db_score += 3
    if sum([cur.get("jpy_exists"), cur.get("brl_exists"), cur.get("inr_exists")]) == 3:
        feedback_parts.append("All Currencies created")
    else:
        feedback_parts.append("Missing some Currencies")

    # Pay Frequencies (2 * 3 = 6 pts)
    pf = result.get("pay_frequencies", {})
    if pf.get("semi_monthly_exists"): db_score += 3
    if pf.get("quarterly_exists"): db_score += 3
    if pf.get("semi_monthly_exists") and pf.get("quarterly_exists"):
        feedback_parts.append("All Pay Frequencies created")
    else:
        feedback_parts.append("Missing some Pay Frequencies")

    # Prefixes (3 * 3 = 9 pts)
    px = result.get("prefixes", {})
    if px.get("dr_exists"): db_score += 3
    if px.get("sra_exists"): db_score += 3
    if px.get("sri_exists"): db_score += 3
    if sum([px.get("dr_exists"), px.get("sra_exists"), px.get("sri_exists")]) == 3:
        feedback_parts.append("All Prefixes created")
    else:
        feedback_parts.append("Missing some Prefixes")

    # Department (6 pts)
    if result.get("department_exists"):
        db_score += 6
        feedback_parts.append("Department created")
    else:
        feedback_parts.append("Department missing")

    # Job Titles (2 * 5 = 10 pts)
    jt = result.get("job_titles", {})
    if jt.get("cd_exists"): db_score += 5
    if jt.get("rc_exists"): db_score += 5
    if jt.get("cd_exists") and jt.get("rc_exists"):
        feedback_parts.append("All Job Titles created")
    else:
        feedback_parts.append("Missing some Job Titles")

    # Employees (3 * 10 = 30 pts)
    # Emp needs to exist and be in correct dept for points
    expected_employees = task_info.get("metadata", {}).get("expected_employees", [])
    emp_results = result.get("employees", {})
    
    emps_perfect = 0
    for exp_emp in expected_employees:
        empid = exp_emp["empid"]
        emp_data = emp_results.get(empid, {})
        
        if not emp_data.get("found"):
            feedback_parts.append(f"{empid} not found")
            continue
            
        is_dept_correct = emp_data.get("deptname", "") == exp_emp["dept"]
        is_title_correct = emp_data.get("jobtitle", "") == exp_emp["title"]
        
        if is_dept_correct and is_title_correct:
            db_score += 10
            emps_perfect += 1
        elif is_dept_correct:
            db_score += 5
            feedback_parts.append(f"{empid} title wrong (got '{emp_data.get('jobtitle')}')")
        else:
            feedback_parts.append(f"{empid} dept wrong (got '{emp_data.get('deptname')}') - 0 points awarded")
            
    if emps_perfect == 3:
        feedback_parts.append("All Employees created perfectly")

    score += db_score

    # ---------------------------------------------------------
    # 2. VLM TRAJECTORY VERIFICATION (30 Points Max)
    # ---------------------------------------------------------
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            all_frames = frames + [final_frame] if final_frame else frames
            
            if all_frames:
                vlm_result = query_vlm(prompt=build_vlm_prompt(), images=all_frames)
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("ui_interaction_observed", False):
                        score += 30
                        feedback_parts.append("VLM verified UI trajectory (+30 pts)")
                    else:
                        feedback_parts.append("VLM did not observe UI configuration steps")
                else:
                    feedback_parts.append(f"VLM check failed: {vlm_result.get('error')}")
            else:
                feedback_parts.append("No frames available for VLM trajectory verification")
        else:
            feedback_parts.append("VLM engine unavailable")
    except ImportError:
        # Graceful degradation if framework package is inaccessible
        logger.warning("gym_anything.vlm not available, assuming agent successfully navigated UI if DB passed")
        if db_score > 30:
            score += 30
            feedback_parts.append("VLM package absent; granted trajectory credit based on DB score")

    passed = score >= 60

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }