#!/usr/bin/env python3
"""
Verifier for compliance_audit_exam_setup task.

Occupation: Compliance Manager (O*NET 13-1041.06)
Industry: Legal / Higher Education / Data Governance

Criteria (25 pts each, pass threshold = 75):
  C1 - Exam configuration 'GDPR Compliant Exam Config' exists (new) with
       a description referencing GDPR / privacy / data protection
  C2 - Connection configuration 'Privacy-First Connection' exists and is active
  C3 - Exam template 'GDPR Exam Template' exists with a 'Last Ping Time' indicator
       named 'Minimal Monitoring'
  C4 - User 'dpo.officer' exists, is active, has EXAM_ADMIN role
"""

import json


_GDPR_KEYWORDS = ['gdpr', 'privacy', 'data protection', 'article 25', 'by design']


def _description_has_gdpr(description: str) -> bool:
    desc_lower = description.lower()
    return any(kw in desc_lower for kw in _GDPR_KEYWORDS)


def verify_compliance_audit_exam_setup(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    PASS_THRESHOLD = 75

    copy_from_env = env_info.get('copy_from_env')
    result_path = '/tmp/compliance_audit_exam_setup_result.json'

    result = {}
    try:
        if copy_from_env:
            local_path = '/tmp/_caes_result_local.json'
            copy_from_env(result_path, local_path)
            with open(local_path) as f:
                result = json.load(f)
        else:
            with open(result_path) as f:
                result = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Could not read result file: {e}'}

    # Gate
    total_new = (
        result.get('new_exam_configs_created', 0)
        + result.get('new_connection_configs_created', 0)
        + result.get('new_templates_created', 0)
        + result.get('new_users_created', 0)
    )
    if total_new == 0:
        return {
            'passed': False, 'score': 0,
            'feedback': 'GATE FAIL: No new entities created.'
        }

    # --- C1: Exam Configuration with GDPR description (25 pts) ---
    if result.get('exam_config_exists'):
        description = result.get('exam_config_description', '')
        has_gdpr_desc = _description_has_gdpr(description)
        if result.get('new_exam_configs_created', 0) > 0 and has_gdpr_desc:
            score += 25
            feedback_parts.append(
                f"C1 PASS: 'GDPR Compliant Exam Config' created with compliance "
                f"description: '{description[:80]}...' (25/25)"
            )
        elif result.get('new_exam_configs_created', 0) > 0:
            score += 15
            feedback_parts.append(
                f"C1 PARTIAL: Config created but description doesn't reference GDPR/privacy "
                f"(got: '{description[:80]}') (15/25)"
            )
        else:
            score += 10
            feedback_parts.append(
                "C1 PARTIAL: Config exists but may be pre-existing (10/25)"
            )
    else:
        feedback_parts.append(
            "C1 FAIL: Exam config 'GDPR Compliant Exam Config' not found (0/25)"
        )

    # --- C2: Connection Configuration (25 pts) ---
    if result.get('connection_config_exists'):
        if result.get('connection_config_active'):
            score += 25
            feedback_parts.append(
                "C2 PASS: 'Privacy-First Connection' created and active (25/25)"
            )
        else:
            score += 15
            feedback_parts.append(
                "C2 PARTIAL: 'Privacy-First Connection' exists but not activated (15/25)"
            )
    else:
        feedback_parts.append(
            "C2 FAIL: Connection config 'Privacy-First Connection' not found (0/25)"
        )

    # --- C3: Template + Minimal Monitoring indicator (25 pts) ---
    tmpl_exists          = result.get('template_exists', False)
    minimal_mon_found    = result.get('minimal_monitoring_found', False)
    last_ping_found      = result.get('last_ping_type_found', False)
    ind_count_on_tmpl    = result.get('indicator_count_on_template', 0)

    if tmpl_exists and minimal_mon_found and last_ping_found:
        score += 25
        feedback_parts.append(
            "C3 PASS: Template 'GDPR Exam Template' exists with 'Minimal Monitoring' "
            "indicator (LAST_PING_TIME) (25/25)"
        )
    elif tmpl_exists and last_ping_found:
        score += 18
        feedback_parts.append(
            f"C3 PARTIAL: Template exists with LAST_PING_TIME indicator but not named "
            f"'Minimal Monitoring' (18/25)"
        )
    elif tmpl_exists and ind_count_on_tmpl > 0:
        score += 12
        feedback_parts.append(
            f"C3 PARTIAL: Template exists with {ind_count_on_tmpl} indicator(s) but "
            f"wrong type (not LAST_PING_TIME) (12/25)"
        )
    elif tmpl_exists:
        score += 8
        feedback_parts.append(
            "C3 PARTIAL: Template 'GDPR Exam Template' exists but no indicators added (8/25)"
        )
    else:
        feedback_parts.append(
            "C3 FAIL: Exam template 'GDPR Exam Template' not found (0/25)"
        )

    # --- C4: User account (25 pts) ---
    user_exists = result.get('user_exists', False)
    user_active = result.get('user_active', False)
    user_role   = result.get('user_role', '')
    has_admin   = 'EXAM_ADMIN' in user_role.upper() if user_role else False

    if user_exists and user_active and has_admin:
        score += 25
        feedback_parts.append(
            f"C4 PASS: User 'dpo.officer' exists, active, role='{user_role}' (25/25)"
        )
    elif user_exists and user_active:
        score += 15
        feedback_parts.append(
            f"C4 PARTIAL: User active but role is '{user_role}' not EXAM_ADMIN (15/25)"
        )
    elif user_exists and has_admin:
        score += 15
        feedback_parts.append(
            "C4 PARTIAL: User has correct role but not activated (15/25)"
        )
    elif user_exists:
        score += 8
        feedback_parts.append(
            f"C4 PARTIAL: User 'dpo.officer' exists but not activated and wrong role (8/25)"
        )
    else:
        feedback_parts.append("C4 FAIL: User 'dpo.officer' not found (0/25)")

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback_parts) or 'No criteria met',
    }
