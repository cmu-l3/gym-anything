#!/usr/bin/env python3
"""
Verifier for full_semester_exam_rollout task.

Occupation: Postsecondary Education Administrator (O*NET 11-9033.00)
Industry: Higher Education

Criteria (25 pts each, pass threshold = 75):
  C1 - Connection config 'Finals Week Secure Config' exists and is active,
       with a fallback URL containing 'whitmore.edu'
  C2 - Exam template 'Final Examination Template' exists (new, not pre-existing)
  C3 - A 'Last Ping Time' monitoring indicator named 'Network Quality Monitor'
       is attached to the exam template
  C4 - User account 'exam.coordinator' exists, is active, has EXAM_ADMIN role
"""

import json
import os


def verify_full_semester_exam_rollout(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    PASS_THRESHOLD = 75

    # --- Load result JSON ---
    copy_from_env = env_info.get('copy_from_env')
    result_path = '/tmp/full_semester_exam_rollout_result.json'

    result = {}
    try:
        if copy_from_env:
            local_path = '/tmp/_fser_result_local.json'
            copy_from_env(result_path, local_path)
            with open(local_path) as f:
                result = json.load(f)
        else:
            # Offline / mock path
            with open(result_path) as f:
                result = json.load(f)
    except Exception as e:
        return {
            'passed': False, 'score': 0,
            'feedback': f'Could not read result file: {e}'
        }

    # --- Wrong-target gate: if zero new entities created overall, score = 0 ---
    new_cc   = result.get('new_connection_configs_created', 0)
    new_tmpl = result.get('new_templates_created', 0)
    new_ind  = result.get('new_indicators_created', 0)
    new_usr  = result.get('new_users_created', 0)
    total_new = new_cc + new_tmpl + new_ind + new_usr

    if total_new == 0:
        return {
            'passed': False, 'score': 0,
            'feedback': 'GATE FAIL: No new entities created. Agent took no action.'
        }

    # --- C1: Connection configuration (25 pts) ---
    if result.get('connection_config_exists'):
        if result.get('connection_config_active'):
            fallback_url = result.get('connection_config_fallback_url', '')
            if 'whitmore.edu' in fallback_url or 'exams' in fallback_url:
                score += 25
                feedback_parts.append(
                    f"C1 PASS: 'Finals Week Secure Config' exists, active, "
                    f"fallback URL='{fallback_url}' (25/25)"
                )
            else:
                score += 15
                feedback_parts.append(
                    f"C1 PARTIAL: Config exists and active but fallback URL unexpected: "
                    f"'{fallback_url}' (15/25)"
                )
        else:
            score += 10
            feedback_parts.append(
                "C1 PARTIAL: 'Finals Week Secure Config' exists but not activated (10/25)"
            )
    else:
        feedback_parts.append(
            "C1 FAIL: Connection config 'Finals Week Secure Config' not found (0/25)"
        )

    # --- C2: Exam template (25 pts) ---
    if result.get('template_exists'):
        if result.get('new_templates_created', 0) > 0:
            score += 25
            feedback_parts.append(
                "C2 PASS: Exam template 'Final Examination Template' created (25/25)"
            )
        else:
            # Template exists but may be pre-existing
            score += 15
            feedback_parts.append(
                "C2 PARTIAL: Template found but may be pre-existing (15/25)"
            )
    else:
        feedback_parts.append(
            "C2 FAIL: Exam template 'Final Examination Template' not found (0/25)"
        )

    # --- C3: Monitoring indicator on template (25 pts) ---
    last_ping_indicator = result.get('last_ping_indicator')
    network_monitor_found = result.get('network_monitor_found', False)
    indicator_count = result.get('indicator_count_on_template', 0)

    if network_monitor_found and last_ping_indicator:
        score += 25
        feedback_parts.append(
            f"C3 PASS: Indicator 'Network Quality Monitor' of type LAST_PING_TIME "
            f"attached to template (25/25)"
        )
    elif last_ping_indicator:
        # Right type but wrong name
        score += 15
        feedback_parts.append(
            f"C3 PARTIAL: LAST_PING_TIME indicator exists on template but not named "
            f"'Network Quality Monitor' (got '{last_ping_indicator.get('name')}') (15/25)"
        )
    elif indicator_count > 0:
        score += 10
        feedback_parts.append(
            f"C3 PARTIAL: {indicator_count} indicator(s) on template but none are "
            f"LAST_PING_TIME type (10/25)"
        )
    else:
        feedback_parts.append(
            "C3 FAIL: No monitoring indicators found on the exam template (0/25)"
        )

    # --- C4: User account (25 pts) ---
    if result.get('user_exists'):
        user_role = result.get('user_role', '')
        is_active = result.get('user_active', False)
        has_admin_role = 'EXAM_ADMIN' in user_role.upper() if user_role else False

        if is_active and has_admin_role:
            score += 25
            feedback_parts.append(
                f"C4 PASS: User 'exam.coordinator' exists, active, role='{user_role}' (25/25)"
            )
        elif is_active:
            score += 15
            feedback_parts.append(
                f"C4 PARTIAL: User 'exam.coordinator' exists and active but role is "
                f"'{user_role}' not EXAM_ADMIN (15/25)"
            )
        elif has_admin_role:
            score += 15
            feedback_parts.append(
                f"C4 PARTIAL: User 'exam.coordinator' has correct role but not activated (15/25)"
            )
        else:
            score += 10
            feedback_parts.append(
                f"C4 PARTIAL: User 'exam.coordinator' exists but not activated and "
                f"role '{user_role}' is wrong (10/25)"
            )
    else:
        feedback_parts.append(
            "C4 FAIL: User account 'exam.coordinator' not found (0/25)"
        )

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback_parts) or 'No criteria met',
    }
