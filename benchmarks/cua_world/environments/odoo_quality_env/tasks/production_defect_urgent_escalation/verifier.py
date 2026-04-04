#!/usr/bin/env python3
"""Verifier for production_defect_urgent_escalation task.

Multi-criterion scoring (100 pts total, pass >= 60):
  C1 (40 pts): Quality check 'Visual Inspection - Cabinet Finish' marked as Failed
               - Failed with substantive notes (>=20 chars): 40 pts
               - Failed but notes missing/trivial: 20 pts
               - Not failed: 0 pts
  C2 (35 pts): New Urgent quality alert created
               - Exists with priority Urgent or Blocker: 35 pts
               - Not found: 0 pts
  C3 (25 pts): New urgent alert has description AND team assigned
               - Has both description (>=20 chars) and team: 25 pts
               - Has description but no team (or no teams available): 15 pts
               - Has team but no description: 10 pts
               - Neither: 0 pts
"""

import json
import os
import tempfile


def verify_production_defect_urgent_escalation(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/production_defect_urgent_escalation_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        os.unlink(tmp.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    # C1: Quality check failed with substantive notes
    check_state = result.get("check_state", "")
    check_note_len = result.get("check_note_length", 0)
    if check_state == "fail":
        if check_note_len >= 20:
            score += 40
            feedback_parts.append(f"Quality check FAILED with notes ({check_note_len} chars) (+40)")
        else:
            score += 20
            feedback_parts.append(f"Quality check FAILED but notes too short ({check_note_len} chars, need >=20) (+20)")
    elif not result.get("check_found"):
        feedback_parts.append("Target quality check not found")
    else:
        feedback_parts.append(f"Quality check state='{check_state}' (expected 'fail')")

    # C2: New Urgent alert exists
    if result.get("new_urgent_alert_found"):
        priority = result.get("new_urgent_alert_priority", "")
        if priority in ("2", "3"):
            score += 35
            p_label = "Urgent" if priority == "2" else "Blocker"
            feedback_parts.append(f"New {p_label} quality alert created (+35)")
        else:
            feedback_parts.append(f"Alert found but priority='{priority}' (expected '2' or '3')")
    else:
        feedback_parts.append("No new Urgent quality alert found")

    # C3: Description + team on the new alert
    if result.get("new_urgent_alert_found"):
        desc_len = result.get("new_urgent_alert_description_length", 0)
        has_team = result.get("new_urgent_alert_has_team", False)
        available_teams = result.get("available_team_ids", [])

        has_desc = desc_len >= 20
        # If no teams exist in system, don't penalize for missing team
        team_possible = len(available_teams) > 0

        if has_desc and (has_team or not team_possible):
            score += 25
            feedback_parts.append(f"Alert has description ({desc_len} chars) and team assignment (+25)")
        elif has_desc and not has_team and team_possible:
            score += 15
            feedback_parts.append(f"Alert has description ({desc_len} chars) but no team assigned (+15)")
        elif has_team and not has_desc:
            score += 10
            feedback_parts.append(f"Alert has team but description too short ({desc_len} chars) (+10)")
        else:
            feedback_parts.append("Alert missing both description and team assignment")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
