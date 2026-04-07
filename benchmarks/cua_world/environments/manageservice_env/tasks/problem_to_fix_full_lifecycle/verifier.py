#!/usr/bin/env python3
"""
Verifier for problem_to_fix_full_lifecycle task.

Stub verifier — real verification is done via external VLM evaluation
using vlm_checklist.json.

Scoring breakdown (100 pts total, pass threshold: 60):
  Criterion 1 (15 pts): Problem created with correct title keywords.
  Criterion 2 (20 pts): Three incidents (1001, 1003, 1004) linked to Problem.
  Criterion 3 (15 pts): Root Cause Analysis documented with bug ID keyword.
  Criterion 4 (15 pts): Emergency Change Request created.
  Criterion 5 (10 pts): Change linked to Problem.
  Criterion 6 (15 pts): KB article created with correct title.
  Criterion 7 (10 pts): Problem status is Resolved.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_problem_to_fix_full_lifecycle(traj, env_info, task_info):
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
            copy_from_env('/tmp/problem_to_fix_full_lifecycle_result.json', result_path)
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
    problem_found = data.get('problem_found', False)
    if not problem_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "FAIL: No Problem record found with relevant title keywords "
                "(expected 'Faulty Network Switch' or 'IDF-A2' or 'Building A Connectivity'). "
                "The agent must create a Problem record for the network switch failure."
            ),
            "subscores": {
                "problem_created": 0,
                "incidents_linked": 0,
                "rca_documented": 0,
                "change_created": 0,
                "change_linked": 0,
                "kb_created": 0,
                "problem_resolved": 0
            }
        }

    # --- Criterion 1 (15 pts): Problem created ---
    score += 15
    subscores['problem_created'] = 15
    problem_title = data.get('problem_title_api', '') or ''
    feedback_parts.append(
        f"PASS: Problem '{problem_title}' created. (+15 pts)"
    )

    # --- Criterion 2 (20 pts): Incidents linked ---
    linked_count = max(
        data.get('incidents_linked_count', 0),
        data.get('problem_linked_target_count', 0),
        data.get('problem_linked_target_count_v2', 0)
    )
    if linked_count >= 3:
        score += 20
        subscores['incidents_linked'] = 20
        feedback_parts.append(
            f"PASS: All 3 target incidents linked to Problem. (+20 pts)"
        )
    elif linked_count >= 1:
        pts = linked_count * 7  # 7 pts per linked incident (partial)
        score += pts
        subscores['incidents_linked'] = pts
        feedback_parts.append(
            f"PARTIAL: {linked_count}/3 target incidents linked. (+{pts} pts)"
        )
    else:
        subscores['incidents_linked'] = 0
        feedback_parts.append(
            f"FAIL: No target incidents linked to Problem. "
            f"Linked IDs: {data.get('problem_linked_request_ids', [])} (+0 pts)"
        )

    # --- Criterion 3 (15 pts): RCA documented ---
    rca_has_content = data.get('rca_has_content', False)
    rca_has_bug_id = data.get('rca_has_bug_id', False)
    if rca_has_content and rca_has_bug_id:
        score += 15
        subscores['rca_documented'] = 15
        feedback_parts.append("PASS: RCA documented with firmware bug ID. (+15 pts)")
    elif rca_has_content:
        score += 8
        subscores['rca_documented'] = 8
        feedback_parts.append("PARTIAL: RCA has content but missing bug ID keyword. (+8 pts)")
    else:
        subscores['rca_documented'] = 0
        feedback_parts.append("FAIL: Root Cause Analysis not documented. (+0 pts)")

    # --- Criterion 4 (15 pts): Change created ---
    change_found = data.get('change_found', False)
    change_type = (data.get('change_type_name', '') or '').lower()
    if change_found:
        if 'emergency' in change_type:
            score += 15
            subscores['change_created'] = 15
            change_title = data.get('change_title_api', '')
            feedback_parts.append(
                f"PASS: Emergency Change '{change_title}' created. (+15 pts)"
            )
        else:
            score += 10
            subscores['change_created'] = 10
            feedback_parts.append(
                f"PARTIAL: Change created but type is '{change_type}', not Emergency. (+10 pts)"
            )
    else:
        subscores['change_created'] = 0
        feedback_parts.append("FAIL: No Change Request found with relevant title. (+0 pts)")

    # --- Criterion 5 (10 pts): Change linked to Problem ---
    change_linked = data.get('change_linked_to_problem', False)
    if change_linked:
        score += 10
        subscores['change_linked'] = 10
        feedback_parts.append("PASS: Change linked to Problem. (+10 pts)")
    else:
        subscores['change_linked'] = 0
        feedback_parts.append("FAIL: Change not linked to Problem record. (+0 pts)")

    # --- Criterion 6 (15 pts): KB article created ---
    kb_found = data.get('kb_found', False)
    if kb_found:
        score += 15
        subscores['kb_created'] = 15
        kb_title = data.get('kb_title_api', '')
        feedback_parts.append(
            f"PASS: KB article '{kb_title}' created. (+15 pts)"
        )
    else:
        subscores['kb_created'] = 0
        feedback_parts.append("FAIL: No KB article found with relevant title. (+0 pts)")

    # --- Criterion 7 (10 pts): Problem resolved ---
    is_resolved = data.get('problem_is_resolved', False)
    if is_resolved:
        score += 10
        subscores['problem_resolved'] = 10
        status_name = data.get('problem_status_name', '')
        feedback_parts.append(
            f"PASS: Problem status is '{status_name}'. (+10 pts)"
        )
    else:
        subscores['problem_resolved'] = 0
        status_name = data.get('problem_status_name', 'unknown')
        feedback_parts.append(
            f"FAIL: Problem status is '{status_name}', not Resolved. (+0 pts)"
        )

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
