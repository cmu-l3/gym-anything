#!/usr/bin/env python3
"""Verifier for vendor_dispute_documentation task.

Multi-criterion scoring (100 pts total, pass >= 60):
  C1 (18 pts): Corrective action added to target alert (>=10 chars)
  C2 (18 pts): Preventive action added to target alert (>=10 chars)
  C3 (14 pts): Priority set to Urgent ('2') or Blocker ('3')
  C4 (15 pts): Partner/vendor assigned to the alert
  C5 (15 pts): Alert transitioned to Done stage
  C6 (20 pts): New Pass/Fail QCP for Acoustic Bloc Screens with failure_message
               - Has passfail type AND failure_message: 20 pts
               - Has passfail type but no failure_message: 10 pts
               - Found but wrong type: 5 pts
"""

import json
import os
import tempfile


def verify_vendor_dispute_documentation(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/vendor_dispute_documentation_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        os.unlink(tmp.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    if not result.get("alert_found"):
        return {"passed": False, "score": 0, "feedback": "Target alert not found — cannot score"}

    # C1: Corrective action
    ca = result.get("corrective_action", "")
    if len(ca) >= 10:
        score += 18
        feedback_parts.append(f"Corrective action added ({len(ca)} chars) (+18)")
    else:
        feedback_parts.append(f"Corrective action missing or too short ({len(ca)} chars)")

    # C2: Preventive action
    pa = result.get("preventive_action", "")
    if len(pa) >= 10:
        score += 18
        feedback_parts.append(f"Preventive action added ({len(pa)} chars) (+18)")
    else:
        feedback_parts.append(f"Preventive action missing or too short ({len(pa)} chars)")

    # C3: Priority Urgent or Blocker
    priority = result.get("priority", "0")
    if priority in ("2", "3"):
        score += 14
        p_label = "Urgent" if priority == "2" else "Blocker"
        feedback_parts.append(f"Priority set to {p_label} (+14)")
    else:
        feedback_parts.append(f"Priority='{priority}' (expected '2' Urgent or '3' Blocker)")

    # C4: Partner assigned
    has_partner = result.get("has_partner", False)
    if has_partner:
        score += 15
        partner_name = result.get("partner_name", "")
        feedback_parts.append(f"Partner '{partner_name}' assigned (+15)")
    else:
        avail = result.get("available_partner_count", 0)
        if avail == 0:
            # No partners available in system — cannot penalize
            score += 15
            feedback_parts.append("No partners available in system, skipping partner check (+15)")
        else:
            feedback_parts.append("No partner assigned to alert")

    # C5: Done stage
    stage_name = (result.get("stage_name") or "").lower()
    stage_id = result.get("stage_id")
    if "done" in stage_name or "close" in stage_name:
        score += 15
        feedback_parts.append(f"Alert in Done stage ('{result.get('stage_name')}') (+15)")
    else:
        feedback_parts.append(f"Alert stage='{result.get('stage_name')}' (expected Done)")

    # C6: New Pass/Fail QCP for Acoustic Bloc Screens
    if result.get("new_passfail_qcp_found"):
        is_pf = result.get("new_passfail_qcp_is_passfail", False)
        has_fm = result.get("new_passfail_qcp_has_failure_message", False)
        if is_pf and has_fm:
            score += 20
            feedback_parts.append(f"New Pass/Fail QCP '{result.get('new_passfail_qcp_name')}' with failure_message (+20)")
        elif is_pf:
            score += 10
            feedback_parts.append(f"New Pass/Fail QCP found but failure_message empty (+10)")
        else:
            score += 5
            feedback_parts.append(f"New QCP found but type='{result.get('new_passfail_qcp_test_type')}' (not Pass/Fail) (+5)")
    else:
        feedback_parts.append("No new Pass/Fail QCP for Acoustic Bloc Screens found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
