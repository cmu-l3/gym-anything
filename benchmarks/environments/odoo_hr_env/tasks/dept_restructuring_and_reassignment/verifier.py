#!/usr/bin/env python3
"""Verifier for dept_restructuring_and_reassignment task.

Multi-criterion scoring (100 pts total, pass >= 60):

  C1 (35 pts): All target employees moved to 'Research & Development'.
               Partial (17 pts): at least 2 of 3 moved correctly.

  C2 (35 pts): All target employees have Marc Demo set as direct manager.
               Partial (17 pts): at least 2 of 3 have correct manager.

  C3 (30 pts): 'R&D USA' department is archived.

Partial max: 17 + 17 + 0 = 34 < 60 (pass threshold). Safe against antipattern 4.
"""

import json
import os
import tempfile


def verify_dept_restructuring(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/dept_restructuring_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        os.unlink(tmp.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    employees = result.get("employees", [])
    total = result.get("target_count", len(employees))

    if total == 0:
        return {"passed": False, "score": 0, "feedback": "No target employees found (setup failure)"}

    # C1: Employees moved to Research & Development
    in_rd_count = sum(1 for e in employees if e.get("in_rd"))
    if in_rd_count == total:
        score += 35
        feedback_parts.append(f"All {total} employees moved to R&D (+35)")
    elif in_rd_count >= 2:
        score += 17
        feedback_parts.append(f"{in_rd_count}/{total} employees moved to R&D, partial (+17)")
    else:
        feedback_parts.append(f"Only {in_rd_count}/{total} employees moved to R&D (+0)")

    # C2: Marc Demo set as direct manager
    marc_manager_count = sum(1 for e in employees if e.get("has_marc_manager"))
    if marc_manager_count == total:
        score += 35
        feedback_parts.append(f"All {total} employees have Marc Demo as manager (+35)")
    elif marc_manager_count >= 2:
        score += 17
        feedback_parts.append(f"{marc_manager_count}/{total} employees have Marc Demo as manager, partial (+17)")
    else:
        feedback_parts.append(f"Only {marc_manager_count}/{total} employees have Marc Demo as manager (+0)")

    # C3: R&D USA department archived
    if result.get("rdu_department_archived"):
        score += 30
        feedback_parts.append("R&D USA department is archived (+30)")
    else:
        feedback_parts.append("R&D USA department is NOT archived (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
