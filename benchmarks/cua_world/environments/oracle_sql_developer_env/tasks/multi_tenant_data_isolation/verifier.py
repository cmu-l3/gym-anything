#!/usr/bin/env python3
"""Verifier for Multi-Tenant Data Isolation task."""

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


def verify_multi_tenant_data_isolation(traj, env_info, task_info):
    """
    Verify Multi-Tenant Data Isolation task.

    Scoring (100 pts total):
    1. Security Flaw Fixes (45 pts):
       a. Policy function fixed (15 pts)
       b. Financial records policy added (15 pts)
       c. Context default fixed (15 pts, partial 5 pts)
    2. Actual Tenant Isolation Verified (20 pts):
       - tenant1_customer_isolated (5 pts)
       - tenant2_customer_isolated (5 pts)
       - tenant3_customer_isolated (5 pts)
       - tenant1_financial_isolated (5 pts)
    3. Security Audit Infrastructure (20 pts):
       - audit_log_table_exists (7 pts)
       - violation_vw_exists (6 pts)
       - audit_proc_exists (7 pts)
    4. GUI Usage (15 pts):
       - 2+ signals for full points

    Pass conditions: score >= 70 AND all 3 security flaws fixed
    (policy_function_fixed AND financial_policy_exists AND context_default_fixed)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/multi_tenant_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # --- Read result fields ---
        policy_function_fixed = result.get('policy_function_fixed', False)
        policy_function_valid = result.get('policy_function_valid', 0)
        financial_policy_exists = result.get('financial_policy_exists', False)
        total_vpd_policies = result.get('total_vpd_policies', 0)
        context_default_fixed = result.get('context_default_fixed', False)
        still_has_zero_default = result.get('still_has_zero_default', True)
        audit_log_table_exists = result.get('audit_log_table_exists', False)
        violation_vw_exists = result.get('violation_vw_exists', False)
        audit_proc_exists = result.get('audit_proc_exists', False)
        tenant1_customer_isolated = result.get('tenant1_customer_isolated', False)
        tenant2_customer_isolated = result.get('tenant2_customer_isolated', False)
        tenant3_customer_isolated = result.get('tenant3_customer_isolated', False)
        tenant1_financial_isolated = result.get('tenant1_financial_isolated', False)
        gui_evidence = result.get('gui_evidence', {})

        # ============================================================
        # Criterion 1: Security Flaw Fixes (45 pts total)
        # ============================================================

        # 1a. Policy function fixed (15 pts)
        if policy_function_fixed and not still_has_zero_default:
            score += 15
            feedback_parts.append(
                f"Policy function fixed, valid={policy_function_valid} (15/15)"
            )
            subscores['policy_function_fixed'] = True
        elif policy_function_fixed:
            # Fixed but zero default still present — no credit
            feedback_parts.append(
                "Policy function marked fixed but zero default still present (0/15)"
            )
            subscores['policy_function_fixed'] = False
        else:
            feedback_parts.append(
                f"Policy function NOT fixed, valid={policy_function_valid} (0/15)"
            )
            subscores['policy_function_fixed'] = False

        # 1b. Financial records policy added (15 pts)
        if financial_policy_exists:
            score += 15
            feedback_parts.append(
                f"Financial records VPD policy exists, total VPD policies={total_vpd_policies} (15/15)"
            )
            subscores['financial_policy_exists'] = True
        else:
            feedback_parts.append(
                f"Financial records VPD policy missing, total VPD policies={total_vpd_policies} (0/15)"
            )
            subscores['financial_policy_exists'] = False

        # 1c. Context default fixed (15 pts, partial 5 pts)
        if context_default_fixed and not still_has_zero_default:
            score += 15
            feedback_parts.append("Context default fixed, no zero default remains (15/15)")
            subscores['context_default_fixed'] = True
        elif context_default_fixed and still_has_zero_default:
            score += 5
            feedback_parts.append(
                "Context default partially fixed but zero default still present (5/15)"
            )
            subscores['context_default_fixed'] = True
        else:
            feedback_parts.append("Context default NOT fixed (0/15)")
            subscores['context_default_fixed'] = False

        # ============================================================
        # Criterion 2: Actual Tenant Isolation Verified (20 pts)
        # ============================================================
        isolation_pts = 0

        if tenant1_customer_isolated:
            isolation_pts += 5
            feedback_parts.append("Tenant 1 customer data isolated (5/5)")
        else:
            feedback_parts.append("Tenant 1 customer data NOT isolated (0/5)")

        if tenant2_customer_isolated:
            isolation_pts += 5
            feedback_parts.append("Tenant 2 customer data isolated (5/5)")
        else:
            feedback_parts.append("Tenant 2 customer data NOT isolated (0/5)")

        if tenant3_customer_isolated:
            isolation_pts += 5
            feedback_parts.append("Tenant 3 customer data isolated (5/5)")
        else:
            feedback_parts.append("Tenant 3 customer data NOT isolated (0/5)")

        if tenant1_financial_isolated:
            isolation_pts += 5
            feedback_parts.append("Tenant 1 financial data isolated (5/5)")
        else:
            feedback_parts.append("Tenant 1 financial data NOT isolated (0/5)")

        score += isolation_pts
        subscores['tenant_isolation'] = isolation_pts
        feedback_parts.append(f"Tenant isolation total: {isolation_pts}/20")

        # ============================================================
        # Criterion 3: Security Audit Infrastructure (20 pts)
        # ============================================================
        audit_pts = 0

        if audit_log_table_exists:
            audit_pts += 7
            feedback_parts.append("Audit log table exists (7/7)")
        else:
            feedback_parts.append("Audit log table missing (0/7)")

        if violation_vw_exists:
            audit_pts += 6
            feedback_parts.append("Violation view exists (6/6)")
        else:
            feedback_parts.append("Violation view missing (0/6)")

        if audit_proc_exists:
            audit_pts += 7
            feedback_parts.append("Audit procedure exists (7/7)")
        else:
            feedback_parts.append("Audit procedure missing (0/7)")

        score += audit_pts
        subscores['audit_infrastructure'] = audit_pts
        feedback_parts.append(f"Audit infrastructure total: {audit_pts}/20")

        # ============================================================
        # Criterion 4: GUI Usage (15 pts)
        # ============================================================
        gui_used, gui_frac, gui_details = _check_gui_usage(gui_evidence)
        gui_pts = int(gui_frac * 15)
        score += gui_pts
        subscores['gui'] = gui_used
        if gui_used:
            feedback_parts.append(f"GUI confirmed ({gui_details}) ({gui_pts}/15)")
        elif gui_pts > 0:
            feedback_parts.append(f"Partial GUI evidence ({gui_details}) ({gui_pts}/15)")
        else:
            feedback_parts.append("No GUI usage evidence (0/15)")

        # ============================================================
        # Optional VLM check
        # ============================================================
        if query_vlm:
            try:
                temp_ss = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_ss.name)
                    vlm_prompt = (
                        "Examine this Oracle SQL Developer screenshot. "
                        "Is there evidence of: VPD policy creation, DBMS_RLS calls, "
                        "SYS_CONTEXT usage, tenant isolation queries, or security audit "
                        "infrastructure visible? "
                        "Reply VERIFIED if multi-tenant data isolation work is visible, "
                        "else NOT_VERIFIED."
                    )
                    vlm_result = query_vlm(image=temp_ss.name, prompt=vlm_prompt)
                    if (vlm_result
                            and 'VERIFIED' in str(vlm_result).upper()
                            and 'NOT_VERIFIED' not in str(vlm_result).upper()):
                        if score < 95:
                            score = min(score + 5, 100)
                            feedback_parts.append(
                                "VLM: multi-tenant isolation work visible (+5 bonus)"
                            )
                finally:
                    os.unlink(temp_ss.name)
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")

        # ============================================================
        # Pass determination
        # ============================================================
        all_security_flaws_fixed = (
            subscores.get('policy_function_fixed', False)
            and subscores.get('financial_policy_exists', False)
            and subscores.get('context_default_fixed', False)
        )

        passed = all_security_flaws_fixed and score >= 70

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
