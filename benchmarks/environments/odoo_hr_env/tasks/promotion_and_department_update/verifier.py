#!/usr/bin/env python3
"""Verifier for promotion_and_department_update task.

Multi-criterion scoring (100 pts total, pass >= 60):

  C1 (30 pts): Ronnie Hart has Job Position = CTO AND is in Management department.
               Partial (15 pts): only one of {CTO, Management dept} is correct.
               (Marc Demo as manager is a bonus but not required for this criterion.)

  C2 (20 pts): Jennie Fletcher has Job Position = HR Manager.

  C3 (30 pts): All Long Term Projects employees have the 'Consultant' tag.
               Partial (15 pts): at least 1 but not all LTP employees have the tag.

  C4 (20 pts): Long Term Projects department has Randall Lewis as its manager.

Partial max: 15 + 0 + 15 + 0 = 30 < 60 (pass threshold). Safe against antipattern 4.
Agent must complete at least 3 criteria or C1+C3 with partial (+15+15+15+15=60) to pass.
"""

import json
import os
import tempfile


def verify_promotion(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/promotion_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        os.unlink(tmp.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    # C1: Ronnie Hart promoted (CTO + Management)
    ronnie = result.get("ronnie_hart", {})
    has_cto = ronnie.get("has_cto", False)
    in_mgmt = ronnie.get("in_management", False)
    if has_cto and in_mgmt:
        score += 30
        feedback_parts.append("Ronnie Hart: CTO + Management dept (+30)")
    elif has_cto or in_mgmt:
        score += 15
        which = "CTO job" if has_cto else "Management dept"
        feedback_parts.append(f"Ronnie Hart: only {which} correct (+15 partial)")
    else:
        feedback_parts.append(f"Ronnie Hart: Job={ronnie.get('job_name')}, Dept={ronnie.get('dept_name')} (neither correct) (+0)")

    # C2: Jennie Fletcher HR Manager
    jennie = result.get("jennie_fletcher", {})
    if jennie.get("has_hr_mgr"):
        score += 20
        feedback_parts.append("Jennie Fletcher: HR Manager (+20)")
    else:
        feedback_parts.append(f"Jennie Fletcher: job={jennie.get('job_name')} (not HR Manager) (+0)")

    # C3: LTP employees have Consultant tag
    ltp_employees = result.get("ltp_employees", [])
    total_ltp = result.get("ltp_total", len(ltp_employees))
    consultant_count = sum(1 for e in ltp_employees if e.get("has_consultant_tag"))
    if total_ltp == 0:
        feedback_parts.append("No LTP employees found (setup issue) (+0)")
    elif consultant_count == total_ltp:
        score += 30
        feedback_parts.append(f"All {total_ltp} LTP employees have Consultant tag (+30)")
    elif consultant_count >= 1:
        score += 15
        feedback_parts.append(f"{consultant_count}/{total_ltp} LTP employees have Consultant tag (+15 partial)")
    else:
        feedback_parts.append(f"No LTP employees have Consultant tag (+0)")

    # C4: LTP department manager is Randall Lewis
    ltp_dept = result.get("ltp_dept", {})
    if ltp_dept.get("has_randall_manager"):
        score += 20
        feedback_parts.append("Long Term Projects dept manager = Randall Lewis (+20)")
    else:
        mgr_name = ltp_dept.get("manager_name") or "not set"
        feedback_parts.append(f"LTP dept manager = {mgr_name} (not Randall Lewis) (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
