#!/usr/bin/env python3
"""
Verifier for sla_compliance_problem_management task.

Scoring breakdown (100 pts total, pass threshold: 60):
  Criterion 1 (30 pts): All 3 target tickets (1001, 1003, 1004) changed from Open status.
                         Partial: 10 pts per ticket (up to 30).
  Criterion 2 (25 pts): All 3 target tickets assigned to a technician (was previously unassigned).
                         Partial: 8 pts per ticket + 1 bonus.
  Criterion 3 (25 pts): Problem record created with title containing 'SLA' and 'failure'/'breach'/'compliance'.
  Criterion 4 (20 pts): At least 2 of the 3 target tickets linked to the Problem.
                         10 pts for 1 linked, 20 pts for 2+.

Wrong-target gate: If none of the 3 target tickets changed status AND no problem was created,
return score=0 immediately (the agent did nothing or worked on wrong items).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60
TARGET_IDS = [1001, 1003, 1004]


def verify_sla_compliance_problem_management(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')

    if copy_from_env is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Verifier error: copy_from_env not available."
        }

    # Pull result JSON from VM
    with tempfile.TemporaryDirectory() as tmp_dir:
        result_path = os.path.join(tmp_dir, 'result.json')
        try:
            copy_from_env('/tmp/sla_compliance_problem_management_result.json', result_path)
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

    # --- Wrong-target gate ---
    # Check if ANY of the 3 target tickets were modified and problem exists
    status_1001 = data.get('status_1001', 2)
    status_1003 = data.get('status_1003', 2)
    status_1004 = data.get('status_1004', 2)
    problem_found = data.get('problem_found', False)

    tickets_changed = sum(1 for s in [status_1001, status_1003, status_1004] if s != 2 and s != 0)

    if tickets_changed == 0 and not problem_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "FAIL: None of the target tickets (1001, 1003, 1004) had their status changed, "
                "and no Problem record was created. The agent appears to have taken no action "
                "on the required items."
            ),
            "subscores": {
                "tickets_status_changed": 0,
                "tickets_assigned": 0,
                "problem_created": 0,
                "problem_linked": 0
            }
        }

    # --- Criterion 1: Status changed from Open (statusid=2) ---
    status_changed_count = 0
    status_name_map = {
        1001: data.get('status_name_1001', ''),
        1003: data.get('status_name_1003', ''),
        1004: data.get('status_name_1004', ''),
    }
    for tid in TARGET_IDS:
        sid = data.get(f'status_{tid}', 2)
        sname = data.get(f'status_name_{tid}', '')
        # Statusid != 2 (Open) OR status name not "Open"
        if sid != 2 and sid != 0 and sid != '':
            status_changed_count += 1
        elif sname and sname.lower() not in ('open', ''):
            status_changed_count += 1

    c1_score = status_changed_count * 10  # 10 pts each, max 30
    score += c1_score
    subscores['tickets_status_changed'] = c1_score

    if status_changed_count == 3:
        feedback_parts.append(f"PASS: All 3 target tickets changed from Open status. (+{c1_score} pts)")
    elif status_changed_count > 0:
        feedback_parts.append(
            f"PARTIAL: {status_changed_count}/3 target tickets changed status. (+{c1_score} pts)"
        )
    else:
        feedback_parts.append(
            f"FAIL: No target tickets changed status. "
            f"Statuses: 1001={status_1001}, 1003={status_1003}, 1004={status_1004}"
        )

    # --- Criterion 2: Technician assigned ---
    # Check both ownerId (SQL) and technician_name (API)
    tech_assigned_count = 0
    for tid in TARGET_IDS:
        owner_id = data.get(f'owner_{tid}', 0)
        tech_name = data.get(f'technician_name_{tid}', '')
        # owner_id > 0 means someone assigned (SQL), or tech_name non-empty (API)
        if (owner_id and str(owner_id) not in ('0', '', 'None')) or (tech_name and tech_name.strip()):
            tech_assigned_count += 1

    c2_score = min(25, tech_assigned_count * 8 + (1 if tech_assigned_count == 3 else 0))
    score += c2_score
    subscores['tickets_assigned'] = c2_score

    if tech_assigned_count == 3:
        feedback_parts.append(f"PASS: All 3 target tickets assigned to a technician. (+{c2_score} pts)")
    elif tech_assigned_count > 0:
        feedback_parts.append(
            f"PARTIAL: {tech_assigned_count}/3 target tickets assigned. (+{c2_score} pts)"
        )
    else:
        feedback_parts.append("FAIL: No target tickets were assigned to a technician. (+0 pts)")

    # --- Criterion 3: Problem record created ---
    if problem_found:
        prob_title = data.get('problem_title', '')
        prob_priority = data.get('problem_priority', '')
        c3_score = 25
        score += c3_score
        subscores['problem_created'] = c3_score
        feedback_parts.append(
            f"PASS: Problem record created: '{prob_title}' "
            f"(priority: {prob_priority}). (+{c3_score} pts)"
        )
    else:
        subscores['problem_created'] = 0
        feedback_parts.append(
            "FAIL: No Problem record found with 'SLA' and 'compliance/failure/breach' in the title. (+0 pts)"
        )

    # --- Criterion 4: Tickets linked to problem ---
    linked_count = max(
        data.get('problem_linked_target_count', 0),
        data.get('problem_linked_target_count_v2', 0)
    )

    if linked_count >= 2:
        c4_score = 20
    elif linked_count == 1:
        c4_score = 10
    else:
        c4_score = 0
    score += c4_score
    subscores['problem_linked'] = c4_score

    if linked_count >= 2:
        feedback_parts.append(
            f"PASS: {linked_count}/3 target tickets linked to the Problem. (+{c4_score} pts)"
        )
    elif linked_count == 1:
        feedback_parts.append(
            f"PARTIAL: Only 1 of 3 target tickets linked to the Problem. (+{c4_score} pts)"
        )
    else:
        feedback_parts.append(
            "FAIL: No target tickets linked to the Problem. (+0 pts) "
            f"(Linked IDs found: {data.get('problem_linked_request_ids', [])})"
        )

    # --- Final result ---
    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
