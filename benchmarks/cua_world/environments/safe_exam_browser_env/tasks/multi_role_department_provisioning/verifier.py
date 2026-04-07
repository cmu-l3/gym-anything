#!/usr/bin/env python3
"""
Verifier for multi_role_department_provisioning task.

Occupation: Information Security Analyst (O*NET 15-1212.00)
Industry: Higher Education / Information Technology

Criteria (pass threshold = 75):
  C1 (20 pts) - At least 3 new user accounts created (baseline delta >= 3)
  C2 (30 pts) - All 4 accounts exist: cs.admin, math.admin, physics.supporter, it.supervisor
  C3 (25 pts) - Correct role assignments:
                  cs.admin + math.admin → EXAM_ADMIN
                  physics.supporter → EXAM_SUPPORTER
                  it.supervisor → INSTITUTIONAL_ADMIN
  C4 (25 pts) - Connection config 'Department Hub Connection Config' exists and is active
"""

import json


def verify_multi_role_department_provisioning(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    PASS_THRESHOLD = 75

    copy_from_env = env_info.get('copy_from_env')
    result_path = '/tmp/multi_role_department_provisioning_result.json'

    result = {}
    try:
        if copy_from_env:
            local_path = '/tmp/_mrdp_result_local.json'
            copy_from_env(result_path, local_path)
            with open(local_path) as f:
                result = json.load(f)
        else:
            with open(result_path) as f:
                result = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Could not read result file: {e}'}

    # Gate
    new_users = result.get('new_users_created', 0)
    new_cc     = result.get('new_connection_configs_created', 0)
    if new_users == 0 and new_cc == 0:
        return {
            'passed': False, 'score': 0,
            'feedback': 'GATE FAIL: No new entities created.'
        }

    users_found  = result.get('users_found', {})
    user_details = result.get('user_details', {})

    # --- C1: At least 3 new users (20 pts) ---
    if new_users >= 4:
        score += 20
        feedback_parts.append(f"C1 PASS: {new_users} new user accounts created (20/20)")
    elif new_users >= 3:
        score += 15
        feedback_parts.append(f"C1 PARTIAL: {new_users}/4 new accounts created (15/20)")
    elif new_users >= 1:
        score += 8
        feedback_parts.append(f"C1 PARTIAL: Only {new_users}/4 accounts created (8/20)")
    else:
        feedback_parts.append("C1 FAIL: No new user accounts created (0/20)")

    # --- C2: All 4 accounts present (30 pts) ---
    accounts_present = sum(1 for v in users_found.values() if v)
    if accounts_present == 4:
        score += 30
        feedback_parts.append(
            "C2 PASS: All 4 accounts found: cs.admin, math.admin, "
            "physics.supporter, it.supervisor (30/30)"
        )
    elif accounts_present == 3:
        score += 20
        missing = [u for u, v in users_found.items() if not v]
        feedback_parts.append(
            f"C2 PARTIAL: 3/4 accounts found, missing: {missing} (20/30)"
        )
    elif accounts_present == 2:
        score += 12
        missing = [u for u, v in users_found.items() if not v]
        feedback_parts.append(
            f"C2 PARTIAL: 2/4 accounts found, missing: {missing} (12/30)"
        )
    elif accounts_present == 1:
        score += 5
        feedback_parts.append("C2 PARTIAL: Only 1/4 accounts found (5/30)")
    else:
        feedback_parts.append("C2 FAIL: None of the expected accounts found (0/30)")

    # --- C3: Role accuracy (25 pts) ---
    expected_roles = {
        'cs.admin': 'EXAM_ADMIN',
        'math.admin': 'EXAM_ADMIN',
        'physics.supporter': 'EXAM_SUPPORTER',
        'it.supervisor': 'INSTITUTIONAL_ADMIN',
    }
    correct_roles = 0
    role_notes = []

    for username, expected_role in expected_roles.items():
        if username not in user_details:
            role_notes.append(f"{username}: missing")
            continue
        actual_role = user_details[username].get('role', '')
        if expected_role.upper() in actual_role.upper():
            correct_roles += 1
            role_notes.append(f"{username}: OK ({actual_role})")
        else:
            role_notes.append(f"{username}: wrong ({actual_role}, expected {expected_role})")

    if correct_roles == 4:
        score += 25
        feedback_parts.append(f"C3 PASS: All 4 roles correct (25/25)")
    elif correct_roles == 3:
        score += 18
        feedback_parts.append(f"C3 PARTIAL: 3/4 correct roles — {'; '.join(role_notes)} (18/25)")
    elif correct_roles == 2:
        score += 10
        feedback_parts.append(f"C3 PARTIAL: 2/4 correct roles — {'; '.join(role_notes)} (10/25)")
    elif correct_roles == 1:
        score += 5
        feedback_parts.append(f"C3 PARTIAL: 1/4 correct roles (5/25)")
    else:
        feedback_parts.append(f"C3 FAIL: No correct role assignments — {'; '.join(role_notes)} (0/25)")

    # --- C4: Connection configuration (25 pts) ---
    if result.get('connection_config_exists'):
        if result.get('connection_config_active'):
            score += 25
            feedback_parts.append(
                "C4 PASS: 'Department Hub Connection Config' exists and is active (25/25)"
            )
        else:
            score += 15
            feedback_parts.append(
                "C4 PARTIAL: 'Department Hub Connection Config' exists but not activated (15/25)"
            )
    else:
        feedback_parts.append(
            "C4 FAIL: Connection config 'Department Hub Connection Config' not found (0/25)"
        )

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback_parts) or 'No criteria met',
    }
