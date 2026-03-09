#!/usr/bin/env python3
"""Verifier for Create PL/SQL Procedure task in Oracle SQL Developer."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_gui_usage(gui_evidence):
    """Check if SQL Developer GUI was actually used."""
    if not gui_evidence:
        return False, 0.0, "No GUI evidence collected"

    signals = 0
    total_signals = 4
    details = []

    if gui_evidence.get('mru_connection_count', 0) > 0:
        signals += 1
        details.append(f"MRU cache: {gui_evidence['mru_connection_count']}")
    if gui_evidence.get('window_title_changed', False):
        signals += 1
        details.append(f"Window: {gui_evidence.get('window_title', '')}")
    if gui_evidence.get('sqldev_oracle_sessions', 0) > 0:
        signals += 1
        details.append(f"{gui_evidence['sqldev_oracle_sessions']} DB sessions")
    if gui_evidence.get('sql_history_count', 0) > 0:
        signals += 1
        details.append(f"{gui_evidence['sql_history_count']} history entries")

    gui_used = signals >= 2
    gui_score = min(signals / total_signals, 1.0)
    return gui_used, gui_score, "; ".join(details) if details else "No GUI interaction"


def verify_create_plsql_procedure(traj, env_info, task_info):
    """
    Verify that a PL/SQL stored procedure was created and executed.

    Criteria (100 pts total):
    1. Procedure exists and is valid (20 pts)
    2. Salaries were updated correctly (10% raise for IT dept) (20 pts)
    3. Procedure was newly created during task (15 pts)
    4. GUI usage verified (25 pts)
    5. VLM verification (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/plsql_proc_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        proc_exists = result.get('procedure_exists', False)
        proc_valid = result.get('procedure_valid', False)
        proc_new = result.get('procedure_newly_created', False)
        salaries_updated = result.get('salaries_updated', False)
        salary_correct = result.get('salary_increase_correct', False)
        gui_evidence = result.get('gui_evidence', {})

        if not proc_exists:
            return {
                "passed": False, "score": 0,
                "feedback": "FAILED: GIVE_DEPARTMENT_RAISE procedure does not exist",
                "subscores": {"procedure_valid": False, "salary_correct": False,
                              "newly_created": False, "gui_verified": False, "vlm_verified": False}
            }

        # Criterion 1: Procedure exists and is valid (20 pts)
        if proc_valid:
            score += 20
            feedback_parts.append("Procedure GIVE_DEPARTMENT_RAISE exists and is VALID")
            subscores['procedure_valid'] = True
        else:
            score += 8
            feedback_parts.append("Procedure exists but status is not VALID (compilation error)")
            subscores['procedure_valid'] = False

        # Criterion 2: Salaries updated correctly (20 pts)
        if salary_correct:
            score += 20
            feedback_parts.append(f"IT dept salaries updated correctly (10% raise: {result.get('initial_salary_sum', 0)} -> {result.get('current_salary_sum', 0)})")
            subscores['salary_correct'] = True
        elif salaries_updated:
            score += 10
            feedback_parts.append(f"Salaries changed but not by expected 10% ({result.get('initial_salary_sum', 0)} -> {result.get('current_salary_sum', 0)})")
            subscores['salary_correct'] = False
        else:
            feedback_parts.append("IT department salaries were not updated")
            subscores['salary_correct'] = False

        # Criterion 3: Procedure newly created (15 pts)
        if proc_new:
            score += 15
            feedback_parts.append("Procedure was created during the task")
            subscores['newly_created'] = True
        elif proc_exists:
            score += 5
            feedback_parts.append("Procedure exists but creation timing uncertain")
            subscores['newly_created'] = False
        else:
            subscores['newly_created'] = False

        # Criterion 4: GUI usage verified (25 pts)
        gui_used, gui_score_frac, gui_details = _check_gui_usage(gui_evidence)
        gui_pts = int(gui_score_frac * 25)
        score += gui_pts
        subscores['gui_verified'] = gui_used
        if gui_used:
            feedback_parts.append(f"GUI confirmed ({gui_details})")
        elif gui_pts > 0:
            feedback_parts.append(f"Partial GUI evidence ({gui_details})")
        else:
            feedback_parts.append("No GUI usage evidence")

        # Criterion 5: VLM verification (20 pts)
        vlm_verified = False
        if query_vlm:
            try:
                temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
                    vlm_prompt = """Analyze this screenshot of Oracle SQL Developer.
                    Questions:
                    1. Is there PL/SQL code visible in a SQL Worksheet or PL/SQL editor?
                    2. Can you see a CREATE PROCEDURE statement or procedure code?
                    3. Are there execution results showing the procedure was compiled or run?
                    4. Can you see GIVE_DEPARTMENT_RAISE or similar procedure name?
                    Respond with "VERIFIED" if PL/SQL procedure work is visible,
                    or "NOT VERIFIED" if not."""
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
            feedback_parts.append("VLM: PL/SQL procedure work visible")
        elif proc_valid and gui_used:
            score += 5
            feedback_parts.append("VLM: Not verified (but procedure + GUI validates)")
        else:
            feedback_parts.append("VLM: Not verified")

        passed = proc_exists and proc_valid and salary_correct and gui_used and score >= 70

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
