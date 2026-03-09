#!/usr/bin/env python3
"""Verifier for Financial Compliance Audit Investigation task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_gui_usage(gui_evidence):
    """Check if SQL Developer GUI was actually used (2+ signals required)."""
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


def verify_financial_audit_investigation(traj, env_info, task_info):
    """
    Verify financial compliance audit task completion.

    Scoring (100 pts total):
    1. Salary audit trigger created and enabled on EMPLOYEES (30 pts)
    2. SALARY_CHANGE_LOG table has correct structure (20 pts)
    3. Audit findings CSV file exported (25 pts)
    4. GUI usage verified (25 pts)

    Pass threshold: 65 pts
    Agent must complete at minimum the trigger + CSV export to pass.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/financial_audit_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        trigger_exists = result.get('trigger_exists', False)
        trigger_enabled = result.get('trigger_enabled', False)
        trigger_on_employees = result.get('trigger_on_employees', False)
        any_salary_trigger = result.get('any_salary_trigger_count', 0) > 0
        log_table_exists = result.get('log_table_exists', False)
        log_has_cols = result.get('log_table_has_salary_cols', False)
        log_entry_count = result.get('log_entry_count', 0)
        csv_exists = result.get('audit_csv_exists', False)
        csv_size = result.get('audit_csv_size', 0)
        csv_salary = result.get('csv_has_salary_data', False)
        csv_expense = result.get('csv_has_expense_data', False)
        gui_evidence = result.get('gui_evidence', {})

        # Criterion 1: SALARY_AUDIT_TRG trigger (30 pts)
        # Accept either exact name or any enabled trigger on EMPLOYEES
        effective_trigger = (trigger_exists and trigger_enabled and trigger_on_employees)
        if effective_trigger:
            score += 30
            feedback_parts.append("SALARY_AUDIT_TRG trigger exists, ENABLED, on EMPLOYEES table (30/30)")
            subscores['trigger'] = True
        elif trigger_exists and trigger_enabled:
            score += 22
            feedback_parts.append("SALARY_AUDIT_TRG exists and ENABLED but table association unclear (22/30)")
            subscores['trigger'] = True
        elif trigger_exists:
            score += 12
            feedback_parts.append("SALARY_AUDIT_TRG exists but not ENABLED (12/30)")
            subscores['trigger'] = False
        elif any_salary_trigger:
            score += 15
            feedback_parts.append("A salary-related trigger exists on EMPLOYEES but not named SALARY_AUDIT_TRG (15/30)")
            subscores['trigger'] = False
        else:
            feedback_parts.append("No SALARY_AUDIT_TRG trigger found on EMPLOYEES (0/30)")
            subscores['trigger'] = False

        # Criterion 2: SALARY_CHANGE_LOG must have actual log entries (20 pts)
        # Table and columns are created by setup — only entries prove the trigger fired.
        # Zero entries = baseline do-nothing state → 0 pts.
        if log_table_exists and log_entry_count > 0 and log_has_cols:
            score += 20
            feedback_parts.append(f"SALARY_CHANGE_LOG has salary columns and {log_entry_count} log entries (20/20)")
            subscores['log_table'] = True
        elif log_table_exists and log_entry_count > 0:
            score += 10
            feedback_parts.append(f"SALARY_CHANGE_LOG has {log_entry_count} entries but missing expected salary columns (10/20)")
            subscores['log_table'] = False
        elif log_table_exists:
            feedback_parts.append("SALARY_CHANGE_LOG exists but 0 log entries — trigger has not fired (0/20)")
            subscores['log_table'] = False
        else:
            feedback_parts.append("SALARY_CHANGE_LOG table not found (0/20)")
            subscores['log_table'] = False

        # Criterion 3: Audit findings CSV (25 pts)
        if csv_exists and csv_size > 200:
            base_pts = 15
            score += base_pts
            subscores['csv'] = True
            msg = f"audit_findings.csv exists ({csv_size} bytes)"
            if csv_salary:
                score += 6
                msg += " + salary violation data present"
            if csv_expense:
                score += 4
                msg += " + expense duplicate data present"
            feedback_parts.append(f"{msg} ({min(base_pts+10, 25)}/25)")
        elif csv_exists:
            score += 5
            feedback_parts.append(f"audit_findings.csv exists but too small ({csv_size} bytes) (5/25)")
            subscores['csv'] = False
        else:
            feedback_parts.append("audit_findings.csv not found at /home/ga/Documents/exports/ (0/25)")
            subscores['csv'] = False

        # Criterion 4: GUI usage (25 pts)
        gui_used, gui_frac, gui_details = _check_gui_usage(gui_evidence)
        gui_pts = int(gui_frac * 25)
        score += gui_pts
        subscores['gui'] = gui_used
        if gui_used:
            feedback_parts.append(f"GUI confirmed ({gui_details}) ({gui_pts}/25)")
        elif gui_pts > 0:
            feedback_parts.append(f"Partial GUI evidence ({gui_details}) ({gui_pts}/25)")
        else:
            feedback_parts.append("No GUI usage evidence (0/25)")

        # VLM check (bonus, not scored separately — absorbed into pass decision)
        if query_vlm:
            try:
                temp_ss = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_ss.name)
                    vlm_prompt = (
                        "Examine this Oracle SQL Developer screenshot. "
                        "Is there evidence of: SQL queries being run against HR tables, "
                        "PL/SQL trigger code, or results showing salary/compliance data? "
                        "Reply VERIFIED if any audit-related SQL work is visible, else NOT_VERIFIED."
                    )
                    vlm_result = query_vlm(image=temp_ss.name, prompt=vlm_prompt)
                    if vlm_result and 'VERIFIED' in str(vlm_result).upper() and 'NOT_VERIFIED' not in str(vlm_result).upper():
                        if score < 95:
                            score = min(score + 5, 100)
                            feedback_parts.append("VLM: audit work visible (+5 bonus)")
                finally:
                    os.unlink(temp_ss.name)
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")

        passed = (
            subscores.get('trigger', False) and
            subscores.get('csv', False) and
            score >= 65
        )

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
