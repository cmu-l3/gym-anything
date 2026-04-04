#!/usr/bin/env python3
"""Verifier for control_point_failure_message_audit task.

Multi-criterion scoring (100 pts total, pass >= 60):
  C1 (40 pts): Failure messages added to target QCPs that lacked them
               - All 3 filled: 40 pts
               - 2/3: 27 pts
               - 1/3: 13 pts
               - 0/3: 0 pts
  C2 (35 pts): New Measure-type QCP for Customizable Desk height check created
               - Exists with measure type: 35 pts
               - Exists but wrong type: 15 pts (agent at least tried)
  C3 (25 pts): New QCP has a non-empty failure message
"""

import json
import os
import tempfile


def verify_control_point_failure_message_audit(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/control_point_failure_message_audit_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        os.unlink(tmp.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    total = result.get("total_target_qcps", 3)
    filled = result.get("filled_count", 0)

    # C1: Failure messages on existing QCPs
    c1_pts = [0, 13, 27, 40]
    pts = c1_pts[min(filled, 3)]
    score += pts
    if pts > 0:
        feedback_parts.append(f"{filled}/{total} target QCPs have failure_message (+{pts})")
    else:
        feedback_parts.append(f"No target QCPs have failure_message added (0/{total})")

    # C2: New Measure-type QCP exists for Customizable Desk
    if result.get("new_measure_qcp_found"):
        if result.get("new_measure_qcp_is_measure_type"):
            score += 35
            feedback_parts.append(f"New Measure-type QCP '{result.get('new_measure_qcp_name')}' found (+35)")
        else:
            score += 15
            feedback_parts.append(
                f"New QCP '{result.get('new_measure_qcp_name')}' found but type='{result.get('new_measure_qcp_test_type')}' (not Measure) (+15)"
            )
    else:
        feedback_parts.append("No new Measure-type QCP for Customizable Desk found")

    # C3: New QCP has failure message
    if result.get("new_measure_qcp_found") and result.get("new_measure_qcp_has_failure_message"):
        score += 25
        feedback_parts.append("New QCP has non-empty failure_message (+25)")
    elif result.get("new_measure_qcp_found"):
        feedback_parts.append("New QCP found but failure_message is empty or too short")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
