#!/usr/bin/env python3
"""
Verifier for medical_licensing_exam_workflow task.

Occupation: Medical and Health Services Manager (O*NET 11-9111.00)
Industry: Healthcare / Medical Education

Criteria (pass threshold = 70):
  C1 (20 pts) - At least one new exam imported from Assessment Tool
  C2 (30 pts) - Two indicators on the imported exam:
                one LAST_PING_TIME ('Latency Monitor') +
                one WARNING_LOG_COUNTER ('Integrity Alert')
  C3 (25 pts) - User 'med.proctor' exists and is active
  C4 (25 pts) - User 'med.proctor' has EXAM_SUPPORTER role
"""

import json


def verify_medical_licensing_exam_workflow(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    PASS_THRESHOLD = 70

    copy_from_env = env_info.get('copy_from_env')
    result_path = '/tmp/medical_licensing_exam_workflow_result.json'

    result = {}
    try:
        if copy_from_env:
            local_path = '/tmp/_mlew_result_local.json'
            copy_from_env(result_path, local_path)
            with open(local_path) as f:
                result = json.load(f)
        else:
            with open(result_path) as f:
                result = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Could not read result file: {e}'}

    # Gate: nothing done at all
    total_new = (
        result.get('new_exams_imported', 0)
        + result.get('new_indicators_created', 0)
        + result.get('new_users_created', 0)
    )
    if total_new == 0:
        return {
            'passed': False, 'score': 0,
            'feedback': 'GATE FAIL: No new entities created.'
        }

    # --- C1: Exam Import (20 pts) ---
    new_exams = result.get('new_exams_imported', 0)
    if new_exams > 0:
        score += 20
        feedback_parts.append(
            f"C1 PASS: {new_exams} exam(s) imported from Assessment Tool (20/20)"
        )
    else:
        feedback_parts.append("C1 FAIL: No new exams imported from Assessment Tool (0/20)")
        # If no import happened, indicators on exam are also impossible
        # Skip C2 in a meaningful way but still check C3/C4

    # --- C2: Two indicators on the imported exam (30 pts) ---
    indicators = result.get('all_exam_indicators', [])
    ind_count  = result.get('indicator_count_on_new_exams', 0)
    lat_found  = result.get('latency_monitor_found', False)
    int_found  = result.get('integrity_alert_found', False)
    last_ping  = result.get('last_ping_type_on_exam', False)
    warn_log   = result.get('warning_log_type_on_exam', False)

    if lat_found and int_found and last_ping and warn_log:
        score += 30
        feedback_parts.append(
            "C2 PASS: Both indicators present on imported exam — "
            "'Latency Monitor' (LAST_PING_TIME) + 'Integrity Alert' (WARNING_LOG_COUNTER) (30/30)"
        )
    elif (last_ping and warn_log) and ind_count >= 2:
        score += 20
        feedback_parts.append(
            f"C2 PARTIAL: Correct indicator types on exam but names differ "
            f"(lat_name={lat_found}, int_name={int_found}) (20/30)"
        )
    elif ind_count >= 2:
        score += 12
        feedback_parts.append(
            f"C2 PARTIAL: 2 indicators on exam but wrong types "
            f"(ping={last_ping}, warn_log={warn_log}) (12/30)"
        )
    elif ind_count == 1:
        score += 8
        feedback_parts.append(
            "C2 PARTIAL: Only 1 indicator found on imported exam (need 2) (8/30)"
        )
    else:
        feedback_parts.append(
            "C2 FAIL: No indicators found on any newly imported exam (0/30)"
        )

    # --- C3: User exists and active (25 pts) ---
    user_exists = result.get('user_exists', False)
    user_active = result.get('user_active', False)

    if user_exists and user_active:
        score += 25
        feedback_parts.append(
            "C3 PASS: User 'med.proctor' exists and is active (25/25)"
        )
    elif user_exists:
        score += 12
        feedback_parts.append(
            "C3 PARTIAL: User 'med.proctor' exists but not activated (12/25)"
        )
    else:
        feedback_parts.append("C3 FAIL: User 'med.proctor' not found (0/25)")

    # --- C4: Correct role (25 pts) ---
    user_role = result.get('user_role', '')
    has_supporter_role = 'SUPPORTER' in user_role.upper() if user_role else False

    if user_exists and has_supporter_role:
        score += 25
        feedback_parts.append(
            f"C4 PASS: User 'med.proctor' has EXAM_SUPPORTER role (got '{user_role}') (25/25)"
        )
    elif user_exists and user_role:
        score += 8
        feedback_parts.append(
            f"C4 PARTIAL: User exists but role is '{user_role}', expected EXAM_SUPPORTER (8/25)"
        )
    else:
        feedback_parts.append("C4 FAIL: User not found or has no role assigned (0/25)")

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback_parts) or 'No criteria met',
    }
