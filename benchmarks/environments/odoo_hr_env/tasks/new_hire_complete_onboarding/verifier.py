#!/usr/bin/env python3
"""Verifier for new_hire_complete_onboarding task.

Multi-criterion scoring (100 pts total, pass >= 60):

  C1 (20 pts): Job Position = 'Experienced Developer' AND Department = 'Research & Development'.
               Partial (10 pts): either job position or department is correct (not both).

  C2 (20 pts): Manager = 'Marc Demo' AND Coach = 'Eli Lambert'.
               Partial (10 pts): either manager or coach is correct (not both).

  C3 (15 pts): Work phone contains the digits of '+1 555 234 5678'
               AND work email = 'jordan.kim@company.com'.

  C4 (15 pts): Both 'Employee' and 'Trainer' tags are assigned.
               Partial (7 pts): exactly one of the two tags is assigned.

  C5 (30 pts): Approved PTO allocation >= 20 days AND approved Comp Days >= 5 days.
               Partial (15 pts): exactly one of the two allocations is correct.

Partial max: 10 + 10 + 0 + 7 + 15 = 42 < 60. Safe against antipattern 4.
Agent must complete at least C1+C2+C3+C4 (70 pts) or similar combination to pass.
"""

import json
import os
import re
import tempfile


def normalize_phone(phone):
    """Strip non-digit characters for flexible phone comparison."""
    return re.sub(r'\D', '', str(phone or ''))


def verify_onboarding(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/onboarding_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        os.unlink(tmp.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    # C1: Job position and department
    correct_job = (result.get('job_id') == result.get('expected_job_id'))
    correct_dept = (result.get('dept_id') == result.get('expected_dept_id'))
    if correct_job and correct_dept:
        score += 20
        feedback_parts.append("Job Position=Experienced Developer AND Dept=R&D (+20)")
    elif correct_job or correct_dept:
        score += 10
        which = "Job Position" if correct_job else "Department"
        feedback_parts.append(f"Only {which} is correct (+10 partial)")
    else:
        feedback_parts.append(f"Job Position and Department incorrect (job={result.get('job_name')}, dept={result.get('dept_name')}) (+0)")

    # C2: Manager and coach
    correct_manager = (result.get('manager_id') == result.get('expected_manager_id'))
    correct_coach = (result.get('coach_id') == result.get('expected_coach_id'))
    if correct_manager and correct_coach:
        score += 20
        feedback_parts.append("Manager=Marc Demo AND Coach=Eli Lambert (+20)")
    elif correct_manager or correct_coach:
        score += 10
        which = "Manager" if correct_manager else "Coach"
        feedback_parts.append(f"Only {which} is correct (+10 partial)")
    else:
        feedback_parts.append(f"Manager and Coach incorrect (+0)")

    # C3: Work phone and email (flexible phone matching)
    expected_phone_digits = normalize_phone('+1 555 234 5678')
    actual_phone_digits = normalize_phone(result.get('work_phone', ''))
    correct_phone = (expected_phone_digits in actual_phone_digits or
                     actual_phone_digits == expected_phone_digits)
    correct_email = (result.get('work_email', '').lower().strip() == 'jordan.kim@company.com')
    if correct_phone and correct_email:
        score += 15
        feedback_parts.append("Work phone and email correct (+15)")
    else:
        missing = []
        if not correct_phone:
            missing.append(f"phone (got: {result.get('work_phone', '')})")
        if not correct_email:
            missing.append(f"email (got: {result.get('work_email', '')})")
        feedback_parts.append(f"Missing: {', '.join(missing)} (+0)")

    # C4: Employee and Trainer tags
    tag_ids = result.get('tag_ids', [])
    has_employee_tag = result.get('expected_employee_tag_id') in tag_ids
    has_trainer_tag = result.get('expected_trainer_tag_id') in tag_ids
    if has_employee_tag and has_trainer_tag:
        score += 15
        feedback_parts.append("Both 'Employee' and 'Trainer' tags assigned (+15)")
    elif has_employee_tag or has_trainer_tag:
        score += 7
        which = "'Employee'" if has_employee_tag else "'Trainer'"
        feedback_parts.append(f"Only {which} tag assigned (+7 partial)")
    else:
        feedback_parts.append("Neither 'Employee' nor 'Trainer' tag assigned (+0)")

    # C5: Leave allocations
    expected_pto = result.get('expected_pto_days', 20)
    expected_comp = result.get('expected_comp_days', 5)
    correct_pto = result.get('max_pto_days', 0) >= expected_pto
    correct_comp = result.get('max_comp_days', 0) >= expected_comp
    if correct_pto and correct_comp:
        score += 30
        feedback_parts.append(f"PTO={result.get('max_pto_days')} days and Comp={result.get('max_comp_days')} days (+30)")
    elif correct_pto or correct_comp:
        score += 15
        which = f"PTO={result.get('max_pto_days')}" if correct_pto else f"Comp={result.get('max_comp_days')}"
        feedback_parts.append(f"Only {which} days correct (+15 partial)")
    else:
        feedback_parts.append(f"No allocations correct (PTO={result.get('max_pto_days')}, Comp={result.get('max_comp_days')}) (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
