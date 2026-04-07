#!/usr/bin/env python3
"""
Verifier for high_stakes_assessment_hardening task.

Occupation: Certification Program Manager (O*NET 13-1041.00)
Industry: Financial Services / Professional Testing

Criteria (25 pts each, pass threshold = 75):
  C1 - Exam configuration 'CPA Board Exam - Maximum Security' created (new entity)
  C2 - Connection configuration 'CPA Exam Connection' created
  C3 - Exam template 'CPA Board Exam Template' created
  C4 - Template has 2 indicators: one LAST_PING_TIME ('Connection Monitor') +
       one ERROR_LOG type ('Security Alert Monitor')
"""

import json


def verify_high_stakes_assessment_hardening(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    PASS_THRESHOLD = 75

    copy_from_env = env_info.get('copy_from_env')
    result_path = '/tmp/high_stakes_assessment_hardening_result.json'

    result = {}
    try:
        if copy_from_env:
            local_path = '/tmp/_hkah_result_local.json'
            copy_from_env(result_path, local_path)
            with open(local_path) as f:
                result = json.load(f)
        else:
            with open(result_path) as f:
                result = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Could not read result file: {e}'}

    # Gate: at least one new entity
    total_new = (
        result.get('new_exam_configs_created', 0)
        + result.get('new_connection_configs_created', 0)
        + result.get('new_templates_created', 0)
        + result.get('new_indicators_created', 0)
    )
    if total_new == 0:
        return {
            'passed': False, 'score': 0,
            'feedback': 'GATE FAIL: No new entities created.'
        }

    # --- C1: Exam Configuration (25 pts) ---
    if result.get('exam_config_exists'):
        if result.get('new_exam_configs_created', 0) > 0:
            score += 25
            feedback_parts.append("C1 PASS: Exam config 'CPA Board Exam - Maximum Security' created (25/25)")
        else:
            score += 15
            feedback_parts.append("C1 PARTIAL: Config found but may be pre-existing (15/25)")
    else:
        feedback_parts.append("C1 FAIL: Exam config 'CPA Board Exam - Maximum Security' not found (0/25)")

    # --- C2: Connection Configuration (25 pts) ---
    if result.get('connection_config_exists'):
        score += 25
        active_note = " (active)" if result.get('connection_config_active') else " (not yet activated)"
        feedback_parts.append(f"C2 PASS: Connection config 'CPA Exam Connection' created{active_note} (25/25)")
    else:
        feedback_parts.append("C2 FAIL: Connection config 'CPA Exam Connection' not found (0/25)")

    # --- C3: Exam Template (25 pts) ---
    if result.get('template_exists'):
        score += 25
        feedback_parts.append("C3 PASS: Exam template 'CPA Board Exam Template' created (25/25)")
    else:
        feedback_parts.append("C3 FAIL: Exam template 'CPA Board Exam Template' not found (0/25)")

    # --- C4: Two indicators with correct names and types (25 pts) ---
    indicators = result.get('indicators_on_template', [])
    ind_count  = result.get('indicator_count_on_template', 0)
    conn_mon   = result.get('connection_monitor_found', False)
    sec_alert  = result.get('security_alert_found', False)
    last_ping  = result.get('last_ping_type_found', False)
    error_log  = result.get('error_log_type_found', False)

    if conn_mon and sec_alert and last_ping and error_log:
        score += 25
        feedback_parts.append(
            "C4 PASS: Both indicators present — 'Connection Monitor' (LAST_PING_TIME) "
            "and 'Security Alert Monitor' (ERROR_LOG_COUNTER) (25/25)"
        )
    elif (last_ping and error_log) or ind_count >= 2:
        score += 15
        feedback_parts.append(
            f"C4 PARTIAL: 2 indicator types present but names may differ from required "
            f"(conn_monitor={conn_mon}, sec_alert={sec_alert}) (15/25)"
        )
    elif ind_count == 1:
        score += 8
        feedback_parts.append(
            f"C4 PARTIAL: Only 1 indicator found on template (need 2) (8/25)"
        )
    else:
        feedback_parts.append("C4 FAIL: No indicators found on the exam template (0/25)")

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback_parts) or 'No criteria met',
    }
