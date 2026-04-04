#!/usr/bin/env python3
"""Verifier for quality_team_audit_setup task.

Multi-criterion scoring (100 pts total, pass >= 60):
  C1 (20 pts): Quality team named 'ISO Surveillance Response Team' exists
  C2 (50 pts): New-stage alerts assigned to that team
               - All assigned: 50 pts
               - >=75%: 38 pts
               - >=50%: 25 pts
               - <50%: 0 pts
  C3 (30 pts): Safety-critical alerts (Weld/Hardware/Cracking) escalated to Urgent
               - All 3 escalated: 30 pts
               - 2/3: 20 pts
               - 1/3: 10 pts
               - 0/3: 0 pts
"""

import json
import os
import tempfile


def verify_quality_team_audit_setup(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/quality_team_audit_setup_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        os.unlink(tmp.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    # C1: Team exists
    if result.get("team_found"):
        score += 20
        feedback_parts.append("'ISO Surveillance Response Team' exists (+20)")
    else:
        feedback_parts.append("'ISO Surveillance Response Team' NOT found — 0 pts for C1 and C2")
        # Without team, C2 is impossible too
        passed = score >= 60
        return {"passed": passed, "score": score, "feedback": "; ".join(feedback_parts)}

    # C2: New-stage alerts assigned to team
    total = result.get("total_new_alerts", 0)
    assigned = result.get("assigned_to_team_count", 0)
    if total > 0:
        ratio = assigned / total
        if ratio >= 1.0:
            score += 50
            feedback_parts.append(f"All {total} New-stage alerts assigned to team (+50)")
        elif ratio >= 0.75:
            score += 38
            feedback_parts.append(f"{assigned}/{total} New-stage alerts assigned to team (+38)")
        elif ratio >= 0.5:
            score += 25
            feedback_parts.append(f"{assigned}/{total} New-stage alerts assigned to team, partial (+25)")
        else:
            feedback_parts.append(f"Only {assigned}/{total} New-stage alerts assigned to team (need >=50%)")
    else:
        feedback_parts.append("No New-stage alerts found to check assignment")

    # C3: Safety-critical alerts escalated to Urgent
    sc_count = result.get("safety_critical_alert_count", 3)
    urgent_count = result.get("safety_urgent_count", 0)
    sc_pts = [0, 10, 20, 30]
    pts = sc_pts[min(urgent_count, 3)]
    score += pts
    if pts > 0:
        feedback_parts.append(f"{urgent_count}/{sc_count} safety-critical alerts at Urgent priority (+{pts})")
    else:
        feedback_parts.append(f"No safety-critical alerts escalated to Urgent (0/{sc_count})")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
