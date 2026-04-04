#!/usr/bin/env python3
"""Verifier for Security Privilege Audit task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_gui_usage(gui_evidence):
    if not gui_evidence:
        return False, 0.0, "No GUI evidence"
    signals = 0
    details = []
    if gui_evidence.get('mru_connection_count', 0) > 0:
        signals += 1
        details.append(f"MRU:{gui_evidence['mru_connection_count']}")
    if gui_evidence.get('sqldev_oracle_sessions', 0) > 0:
        signals += 1
        details.append(f"sessions:{gui_evidence['sqldev_oracle_sessions']}")
    if gui_evidence.get('sql_history_count', 0) > 0:
        signals += 1
        details.append(f"history:{gui_evidence['sql_history_count']}")
    gui_used = signals >= 2
    return gui_used, min(signals / 3, 1.0), "; ".join(details) or "No signals"


def verify_security_privilege_audit(traj, env_info, task_info):
    """
    Verify Oracle database security privilege audit and remediation task.

    Scoring (100 pts total):
    1. DEV_USER remediated: DBA role revoked (20 pts)
    2. REPORT_USER2 remediated: CREATE TABLE + SELECT ANY TABLE revoked (15 pts)
    3. APP_USER remediated: RESOURCE + UNLIMITED TABLESPACE revoked (15 pts)
    4. LEGACY_USER locked (10 pts)
    5. PRIVILEGE_ESCALATION_AUDIT policy exists and enabled (15 pts)
    6. GUI usage verified (25 pts)

    Note: ANALYST_USER remediation is a bonus (partial credit absorbed into other criteria).
    Pass threshold: 60 pts
    Agent must remediate at least DEV_USER + one other user + configure audit to pass.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/security_privilege_audit_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        dev_exists = result.get('dev_user_exists', False)
        dev_has_dba = result.get('dev_has_dba', True)
        dev_sys_priv_count = result.get('dev_sys_priv_count', 99)
        dev_role_count = result.get('dev_role_count', 99)

        report_has_create_table = result.get('report_has_create_table', True)
        report_has_select_any = result.get('report_has_select_any', True)
        report_exists = result.get('report_user2_exists', False)

        analyst_has_alter_system = result.get('analyst_has_alter_system', True)
        analyst_has_select_dict = result.get('analyst_has_select_dict', True)
        analyst_has_create_table = result.get('analyst_has_create_table', True)

        app_has_resource = result.get('app_has_resource', True)
        app_has_unlimited = result.get('app_has_unlimited_tablespace', True)
        app_exists = result.get('app_user_exists', False)

        legacy_is_locked = result.get('legacy_is_locked', False)
        legacy_exists = result.get('legacy_user_exists', False)
        legacy_status = result.get('legacy_account_status', 'OPEN')

        audit_policy_exists = result.get('audit_policy_exists', False)
        audit_policy_enabled = result.get('audit_policy_enabled', False)
        audit_has_grant = result.get('audit_has_grant_any_privilege', False)
        audit_has_create_user = result.get('audit_has_create_user', False)
        audit_has_drop_user = result.get('audit_has_drop_user', False)
        audit_has_alter_user = result.get('audit_has_alter_user', False)
        audit_has_create_role = result.get('audit_has_create_role', False)

        report_file_exists = result.get('report_exists', False)
        report_size = result.get('report_size', 0)
        report_mentions_dev = result.get('report_mentions_dev_user', False)
        report_mentions_audit = result.get('report_mentions_audit', False)

        gui_evidence = result.get('gui_evidence', {})

        # Criterion 1: DEV_USER remediated (20 pts)
        # DBA role must be revoked; account should still exist
        if dev_exists and not dev_has_dba and dev_role_count == 0:
            score += 20
            feedback_parts.append(f"DEV_USER fully remediated: DBA revoked, no roles remain (20/20)")
            subscores['dev_user'] = True
        elif dev_exists and not dev_has_dba:
            score += 15
            feedback_parts.append(f"DEV_USER: DBA role revoked but {dev_role_count} other role(s) remain (15/20)")
            subscores['dev_user'] = True
        elif dev_exists and dev_has_dba:
            feedback_parts.append("DEV_USER still has DBA role — not remediated (0/20)")
            subscores['dev_user'] = False
        elif not dev_exists:
            # Dropped the user — partial credit (dropping vs revoking is a different action but works)
            score += 10
            feedback_parts.append("DEV_USER was dropped (account should be kept but remediated) (10/20)")
            subscores['dev_user'] = True

        # Criterion 2: REPORT_USER2 remediated (15 pts)
        if not report_has_create_table and not report_has_select_any:
            score += 15
            feedback_parts.append("REPORT_USER2: CREATE TABLE and SELECT ANY TABLE both revoked (15/15)")
            subscores['report_user2'] = True
        elif not report_has_select_any:
            score += 8
            feedback_parts.append("REPORT_USER2: SELECT ANY TABLE revoked but CREATE TABLE remains (8/15)")
            subscores['report_user2'] = False
        elif not report_has_create_table:
            score += 5
            feedback_parts.append("REPORT_USER2: CREATE TABLE revoked but SELECT ANY TABLE remains (5/15)")
            subscores['report_user2'] = False
        else:
            feedback_parts.append("REPORT_USER2: CREATE TABLE and SELECT ANY TABLE still present (0/15)")
            subscores['report_user2'] = False

        # Criterion 3: APP_USER remediated (15 pts)
        if not app_has_resource and not app_has_unlimited:
            score += 15
            feedback_parts.append("APP_USER: RESOURCE role and UNLIMITED TABLESPACE both revoked (15/15)")
            subscores['app_user'] = True
        elif not app_has_resource:
            score += 8
            feedback_parts.append("APP_USER: RESOURCE role revoked but UNLIMITED TABLESPACE remains (8/15)")
            subscores['app_user'] = False
        elif not app_has_unlimited:
            score += 5
            feedback_parts.append("APP_USER: UNLIMITED TABLESPACE revoked but RESOURCE role remains (5/15)")
            subscores['app_user'] = False
        else:
            feedback_parts.append("APP_USER: RESOURCE and UNLIMITED TABLESPACE still present (0/15)")
            subscores['app_user'] = False

        # Criterion 4: LEGACY_USER locked (10 pts)
        if legacy_exists and legacy_is_locked:
            score += 10
            feedback_parts.append(f"LEGACY_USER locked (status: {legacy_status}) (10/10)")
            subscores['legacy_user'] = True
        elif legacy_exists and not legacy_is_locked:
            feedback_parts.append(f"LEGACY_USER exists but not locked (status: {legacy_status}) (0/10)")
            subscores['legacy_user'] = False
        elif not legacy_exists:
            # Should be locked not dropped
            feedback_parts.append("LEGACY_USER was dropped (should be locked, not dropped) (0/10)")
            subscores['legacy_user'] = False

        # Criterion 5: Audit policy (15 pts)
        audit_privilege_count = sum([
            audit_has_grant, audit_has_create_user, audit_has_drop_user,
            audit_has_alter_user, audit_has_create_role
        ])
        if audit_policy_exists and audit_policy_enabled and audit_privilege_count >= 4:
            score += 15
            covered = []
            if audit_has_grant: covered.append("GRANT ANY PRIVILEGE")
            if audit_has_create_user: covered.append("CREATE USER")
            if audit_has_drop_user: covered.append("DROP USER")
            if audit_has_alter_user: covered.append("ALTER USER")
            if audit_has_create_role: covered.append("CREATE ROLE")
            feedback_parts.append(f"PRIVILEGE_ESCALATION_AUDIT policy enabled, covers {audit_privilege_count}/5 required privileges (15/15)")
            subscores['audit_policy'] = True
        elif audit_policy_exists and audit_policy_enabled:
            score += 8
            feedback_parts.append(f"PRIVILEGE_ESCALATION_AUDIT policy enabled but covers only {audit_privilege_count}/5 required privileges (8/15)")
            subscores['audit_policy'] = False
        elif audit_policy_exists:
            score += 5
            feedback_parts.append(f"PRIVILEGE_ESCALATION_AUDIT policy exists but NOT enabled (5/15)")
            subscores['audit_policy'] = False
        else:
            feedback_parts.append("PRIVILEGE_ESCALATION_AUDIT audit policy not found (0/15)")
            subscores['audit_policy'] = False

        # Criterion 6: GUI usage (25 pts)
        gui_used, gui_frac, gui_details = _check_gui_usage(gui_evidence)
        gui_pts = int(gui_frac * 25)
        score += gui_pts
        subscores['gui'] = gui_used
        if gui_used:
            feedback_parts.append(f"GUI confirmed ({gui_details}) ({gui_pts}/25)")
        elif gui_pts > 0:
            feedback_parts.append(f"Partial GUI evidence ({gui_details}) ({gui_pts}/25)")
        else:
            feedback_parts.append(f"No GUI usage evidence (0/25)")

        # VLM bonus
        if query_vlm:
            try:
                temp_ss = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_ss.name)
                    vlm_prompt = (
                        "Examine this Oracle SQL Developer screenshot. "
                        "Is there evidence of: REVOKE statements, ALTER USER commands, "
                        "CREATE AUDIT POLICY statements, or DBA_SYS_PRIVS/DBA_ROLE_PRIVS query results visible? "
                        "Reply VERIFIED if privilege management or audit configuration work is visible, else NOT_VERIFIED."
                    )
                    vlm_result = query_vlm(image=temp_ss.name, prompt=vlm_prompt)
                    if vlm_result and 'VERIFIED' in str(vlm_result).upper() and 'NOT_VERIFIED' not in str(vlm_result).upper():
                        if score < 95:
                            score = min(score + 5, 100)
                            feedback_parts.append("VLM: privilege management work visible (+5 bonus)")
                finally:
                    os.unlink(temp_ss.name)
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")

        # Pass: DEV_USER must be remediated + score >= 60
        users_remediated = sum([
            subscores.get('dev_user', False),
            subscores.get('report_user2', False),
            subscores.get('app_user', False),
            subscores.get('legacy_user', False),
        ])

        passed = (
            subscores.get('dev_user', False) and
            users_remediated >= 2 and
            score >= 60
        )

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
