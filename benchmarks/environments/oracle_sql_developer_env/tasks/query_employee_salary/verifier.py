#!/usr/bin/env python3
"""Verifier for Query Employee Salary task in Oracle SQL Developer."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

KNOWN_FINANCE_EMPLOYEES = ["Greenberg", "Faviet", "Chen", "Sciarra", "Urman"]


def _check_gui_usage(gui_evidence):
    """Check if SQL Developer GUI was actually used (not just command-line tools).

    Returns (gui_used: bool, gui_score: float 0-1, details: str)
    """
    if not gui_evidence:
        return False, 0.0, "No GUI evidence collected"

    signals = 0
    total_signals = 4
    details = []

    mru = gui_evidence.get('mru_connection_count', 0)
    if mru > 0:
        signals += 1
        details.append(f"MRU cache has {mru} connections")

    if gui_evidence.get('window_title_changed', False):
        signals += 1
        details.append(f"Window title: {gui_evidence.get('window_title', '')}")

    sessions = gui_evidence.get('sqldev_oracle_sessions', 0)
    if sessions > 0:
        signals += 1
        details.append(f"{sessions} active SQL Developer DB sessions")

    history = gui_evidence.get('sql_history_count', 0)
    if history > 0:
        signals += 1
        details.append(f"{history} SQL history entries")

    gui_used = signals >= 2
    gui_score = min(signals / total_signals, 1.0)
    detail_str = "; ".join(details) if details else "No GUI interaction detected"
    return gui_used, gui_score, detail_str


def verify_query_employee_salary(traj, env_info, task_info):
    """
    Verify that a salary query was executed and results exported.

    Criteria (100 pts total):
    1. Output file exists at correct path (15 pts)
    2. Correct row count (exactly 5 Finance employees with salary > 7000) (20 pts)
    3. Known employee names present in output (20 pts)
    4. GUI usage verified (25 pts)
    5. VLM verification of query results (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')
    metadata = task_info.get('metadata', {})

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/salary_query_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        output_file_exists = result.get('output_file_exists', False)
        output_row_count = result.get('output_row_count', 0)
        correct_count = result.get('correct_count', False)
        known_matched = result.get('known_employees_matched', 0)
        employees_found = result.get('employees_found', '')
        gui_evidence = result.get('gui_evidence', {})

        logger.info(f"Result: file={output_file_exists}, rows={output_row_count}, "
                    f"matched={known_matched}, gui={gui_evidence}")

        # CRITICAL: Output file must exist
        if not output_file_exists:
            return {
                "passed": False, "score": 0,
                "feedback": "FAILED: Output file not found at /home/ga/Documents/exports/finance_high_salary.csv",
                "subscores": {"output_file": False, "correct_count": False,
                              "employees_validated": False, "gui_verified": False, "vlm_verified": False}
            }

        # Criterion 1: Output file exists at correct path (15 pts)
        score += 15
        feedback_parts.append("Output file exists at correct path")
        subscores['output_file'] = True

        # Criterion 2: Correct row count - exactly 5 (20 pts)
        if correct_count:
            score += 20
            feedback_parts.append(f"Row count correct: {output_row_count}")
            subscores['correct_count'] = True
        elif output_row_count > 0:
            score += 5
            feedback_parts.append(f"WRONG COUNT: {output_row_count} rows (expected exactly 5)")
            subscores['correct_count'] = False
        else:
            feedback_parts.append("Output file is empty")
            subscores['correct_count'] = False

        # Criterion 3: Known employees validated (need at least 4 of 5) (20 pts)
        min_required = 4
        if known_matched >= 5:
            score += 20
            feedback_parts.append(f"All 5 employees validated ({employees_found})")
            subscores['employees_validated'] = True
        elif known_matched >= min_required:
            score += 15
            feedback_parts.append(f"Most employees validated: {known_matched}/5 ({employees_found})")
            subscores['employees_validated'] = True
        elif known_matched > 0:
            score += 5
            feedback_parts.append(f"Partial match: {known_matched}/5 ({employees_found})")
            subscores['employees_validated'] = False
        else:
            feedback_parts.append("No known Finance employees found in output")
            subscores['employees_validated'] = False

        # Criterion 4: GUI usage verified (25 pts) - CRITICAL
        gui_used, gui_score_frac, gui_details = _check_gui_usage(gui_evidence)
        gui_pts = int(gui_score_frac * 25)
        score += gui_pts
        subscores['gui_verified'] = gui_used
        if gui_used:
            feedback_parts.append(f"GUI usage confirmed ({gui_details})")
        elif gui_pts > 0:
            feedback_parts.append(f"Partial GUI evidence ({gui_details})")
        else:
            feedback_parts.append("No GUI usage evidence - task may have been done via command line")

        # Criterion 5: VLM verification (20 pts)
        vlm_verified = False
        if query_vlm:
            try:
                temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
                    vlm_prompt = """Analyze this screenshot of Oracle SQL Developer.
                    Questions:
                    1. Is there a SQL Worksheet visible with a SQL query?
                    2. Are there query results visible in a data grid?
                    3. Does the data show employee salary information?
                    4. Can you see names like Greenberg, Faviet, Chen?
                    Respond with "VERIFIED" if query results with salary data are visible,
                    or "NOT VERIFIED" if no results are visible."""
                    vlm_result = query_vlm(image=temp_screenshot.name, prompt=vlm_prompt)
                    if vlm_result:
                        vlm_text = str(vlm_result).upper()
                        if 'VERIFIED' in vlm_text and 'NOT VERIFIED' not in vlm_text:
                            vlm_verified = True
                finally:
                    os.unlink(temp_screenshot.name)
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")

        subscores['vlm_verified'] = vlm_verified
        if vlm_verified:
            score += 20
            feedback_parts.append("VLM: Query results visible")
        elif output_file_exists and correct_count and gui_used:
            score += 5
            feedback_parts.append("VLM: Not verified (but output + GUI validates)")
        else:
            feedback_parts.append("VLM: Not verified")

        passed = (
            output_file_exists and
            correct_count and
            known_matched >= min_required and
            gui_used and
            score >= 75
        )

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {e}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}
