#!/usr/bin/env python3
"""Verifier for annual_leave_audit_and_correction task.

Multi-criterion scoring (100 pts total, pass >= 60):

  C1 (60 pts): All 4 Sales employees have an approved PTO allocation >= 20 days.
               Partial (30 pts): exactly 2 or 3 of 4 have sufficient PTO.

  C2 (40 pts): All 4 Sales employees have the 'Sales' tag.
               Partial (20 pts): exactly 2 or 3 of 4 have the Sales tag.

Partial max: 30 + 20 = 50 < 60 (pass threshold). Safe against antipattern 4.
To pass, agent must complete most of both criteria (e.g., all 4 PTO correct = 60 pts alone).
"""

import json
import os
import tempfile


def verify_leave_audit(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/leave_audit_result.json", tmp.name)
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

    # C1: Sufficient PTO allocation
    pto_ok_count = sum(1 for e in employees if e.get("has_sufficient_pto"))
    if pto_ok_count == total:
        score += 60
        feedback_parts.append(f"All {total} Sales employees have >= 20-day PTO allocation (+60)")
    elif pto_ok_count >= 2:
        score += 30
        feedback_parts.append(f"{pto_ok_count}/{total} employees have sufficient PTO, partial (+30)")
    else:
        feedback_parts.append(f"Only {pto_ok_count}/{total} employees have sufficient PTO (+0)")

    # C2: Sales tag present
    tag_ok_count = sum(1 for e in employees if e.get("has_sales_tag"))
    if tag_ok_count == total:
        score += 40
        feedback_parts.append(f"All {total} Sales employees have 'Sales' tag (+40)")
    elif tag_ok_count >= 2:
        score += 20
        feedback_parts.append(f"{tag_ok_count}/{total} employees have Sales tag, partial (+20)")
    else:
        feedback_parts.append(f"Only {tag_ok_count}/{total} employees have Sales tag (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
