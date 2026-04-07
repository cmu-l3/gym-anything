#!/usr/bin/env python3
"""
Verifier for dept_restructure_workforce_reallocation task.

Context: Westbrook University HR must create 2 new Engineering sub-units
and reassign 3 faculty staff members to the correct sub-unit.

Scoring (100 pts total, pass threshold 70):

Sub-unit creation:
  - 'Engineering - Backend Systems' sub-unit exists:  20 pts
  - 'Engineering - Applied Research' sub-unit exists:  20 pts
  Subtotal: 40 pts

Employee reassignment:
  - James Anderson (EMP001) → Engineering - Backend Systems:       20 pts
  - Christopher Williams (EMP009) → Engineering - Backend Systems: 20 pts
  - Daniel Wilson (EMP013) → Engineering - Applied Research:       20 pts
  Partial: wrong Engineering sub-unit assigned = 5 pts each
  Subtotal: 60 pts

Total: 100 pts. Pass threshold: 70

Anti-Pattern 4 check (strategy enumeration):
  Only 1 sub-unit created + all 3 in Backend (2 correct, 1 partial):
    20 (backend) + 0 (no research) + 20 + 20 + 5 = 65 < 70 ✓
  Both sub-units + all 3 in Backend (2 correct, 1 partial):
    40 + 20 + 20 + 5 = 85 → pass ✓ (genuinely good partial result)
  Do-nothing: score=0 (sub-units don't exist, employees still in Engineering).
"""

import json
import os
import tempfile


def verify_dept_restructure_workforce_reallocation(traj, env_info, task_info):
    result_path = task_info.get("metadata", {}).get(
        "result_file", "/tmp/dept_restructure_workforce_reallocation_result.json"
    )

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_path, local_tmp)
        with open(local_tmp, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file '{result_path}': {e}",
        }
    finally:
        if os.path.exists(local_tmp):
            os.remove(local_tmp)

    score = 0
    feedback_parts = []

    # -------------------------------------------------------
    # Sub-unit existence checks
    # -------------------------------------------------------
    backend_exists = data.get("backend_subunit_exists", False)
    if backend_exists is True or backend_exists == "true":
        score += 20
        feedback_parts.append("PASS 'Engineering - Backend Systems' sub-unit created (+20)")
    else:
        feedback_parts.append("FAIL 'Engineering - Backend Systems' sub-unit not found (+0)")

    research_exists = data.get("research_subunit_exists", False)
    if research_exists is True or research_exists == "true":
        score += 20
        feedback_parts.append("PASS 'Engineering - Applied Research' sub-unit created (+20)")
    else:
        feedback_parts.append("FAIL 'Engineering - Applied Research' sub-unit not found (+0)")

    # -------------------------------------------------------
    # Employee assignment checks
    # -------------------------------------------------------
    def check_assignment(name, dept_key, expected_substring, pts):
        nonlocal score
        dept = (data.get(dept_key) or "").strip()
        if expected_substring.lower() in dept.lower():
            score += pts
            feedback_parts.append(f"PASS {name} assigned to '{dept}' (contains '{expected_substring}') (+{pts})")
        elif "engineering" in dept.lower() and dept.lower() != "engineering":
            # Assigned to an Engineering sub-unit but wrong one — partial credit
            score += 5
            feedback_parts.append(
                f"PARTIAL {name} assigned to Engineering sub-unit '{dept}' but wrong one (expected '{expected_substring}') (+5)"
            )
        else:
            feedback_parts.append(
                f"FAIL {name} dept='{dept}' — expected '{expected_substring}' (+0)"
            )

    check_assignment("James Anderson (EMP001)", "james_dept", "Backend Systems", 20)
    check_assignment("Christopher Williams (EMP009)", "chris_dept", "Backend Systems", 20)
    check_assignment("Daniel Wilson (EMP013)", "daniel_dept", "Applied Research", 20)

    score = min(score, 100)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
