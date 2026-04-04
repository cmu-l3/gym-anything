#!/usr/bin/env python3
"""
Verifier for change_request_full_lifecycle task.

Scoring breakdown (100 pts total, pass threshold: 60):
  Criterion 1 (30 pts): Change Request created with 'Campus Network' or 'Switch Replacement' in title.
                         +10 bonus if it's a Normal change type.
  Criterion 2 (20 pts): Change has at least 1 Change Task created.
  Criterion 3 (20 pts): VPN ticket (1004) linked to the Change as a related incident.
  Criterion 4 (20 pts): Change status set to 'Requested' (submitted for CAB review).
  Criterion 5 (10 pts): Change has reason_for_change AND at least one of rollout/backout plan filled in.

Wrong-target gate: If no Change record with the relevant title keyword was found,
return score=0 — the agent created a change for the wrong thing or didn't create one at all.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_change_request_full_lifecycle(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')

    if copy_from_env is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Verifier error: copy_from_env not available."
        }

    with tempfile.TemporaryDirectory() as tmp_dir:
        result_path = os.path.join(tmp_dir, 'result.json')
        try:
            copy_from_env('/tmp/change_request_full_lifecycle_result.json', result_path)
            with open(result_path) as f:
                data = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not read result file from VM: {e}"
            }

    score = 0
    feedback_parts = []
    subscores = {}

    change_found = data.get('change_found', False)

    # --- Wrong-target gate ---
    if not change_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "FAIL: No Change Request found with 'Campus Network' or 'Switch Replacement' in the title. "
                "The agent must create a Change Request for the campus network switch replacement. "
                "A change with a different or unrelated title does not satisfy this task."
            ),
            "subscores": {
                "change_created": 0,
                "change_tasks": 0,
                "incident_linked": 0,
                "change_submitted": 0,
                "change_details": 0
            }
        }

    # --- Criterion 1: Change created (with type bonus) ---
    c1_score = 30
    score += c1_score
    subscores['change_created'] = c1_score

    change_title = data.get('change_title_api', '') or ''
    change_type = data.get('change_type_name', '')
    type_msg = f" (type: {change_type})" if change_type else ""

    if change_type.lower() == 'normal':
        feedback_parts.append(
            f"PASS: Change Request '{change_title}' created as Normal change{type_msg}. (+{c1_score} pts)"
        )
    else:
        feedback_parts.append(
            f"PASS: Change Request '{change_title}' created{type_msg}. "
            f"Note: should be 'Normal' type. (+{c1_score} pts)"
        )

    # --- Criterion 2: Change tasks exist ---
    task_count = data.get('change_task_count', 0)
    if task_count >= 1:
        score += 20
        subscores['change_tasks'] = 20
        feedback_parts.append(f"PASS: {task_count} Change Task(s) added to the change. (+20 pts)")
    else:
        subscores['change_tasks'] = 0
        feedback_parts.append(
            "FAIL: No Change Tasks found for this Change Request. "
            "At least one task (e.g., 'Pre-deployment configuration backup') is required. (+0 pts)"
        )

    # --- Criterion 3: VPN ticket linked ---
    vpn_linked = data.get('vpn_ticket_linked', False)
    if vpn_linked:
        score += 20
        subscores['incident_linked'] = 20
        feedback_parts.append("PASS: VPN ticket (1004) linked to the Change as a related incident. (+20 pts)")
    else:
        subscores['incident_linked'] = 0
        feedback_parts.append(
            "FAIL: VPN connectivity ticket (1004) not linked to the Change. "
            f"Linked IDs found: {data.get('linked_request_ids_api', [])} (+0 pts)"
        )

    # --- Criterion 4: Status is "Requested" ---
    status_requested = data.get('change_status_is_requested', False)
    status_name = data.get('change_status_name', '')
    if status_requested:
        score += 20
        subscores['change_submitted'] = 20
        feedback_parts.append(f"PASS: Change status is '{status_name}' (submitted for CAB review). (+20 pts)")
    else:
        subscores['change_submitted'] = 0
        feedback_parts.append(
            f"FAIL: Change status is '{status_name}', not 'Requested'. "
            "The change must be submitted for CAB review. (+0 pts)"
        )

    # --- Criterion 5: Reason + plan filled in ---
    has_reason = data.get('has_reason', False)
    has_rollout = data.get('has_rollout_plan', False)
    has_backout = data.get('has_backout_plan', False)
    has_details = has_reason and (has_rollout or has_backout)

    if has_details:
        score += 10
        subscores['change_details'] = 10
        feedback_parts.append(
            f"PASS: Change has reason and plan details filled in. "
            f"(reason={has_reason}, rollout={has_rollout}, backout={has_backout}) (+10 pts)"
        )
    elif has_reason:
        score += 5
        subscores['change_details'] = 5
        feedback_parts.append(
            "PARTIAL: Change has reason but no rollout/backout plan. (+5 pts)"
        )
    else:
        subscores['change_details'] = 0
        feedback_parts.append(
            "FAIL: Change is missing reason_for_change and plan details. (+0 pts)"
        )

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
