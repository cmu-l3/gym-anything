#!/usr/bin/env python3
"""Verifier for Manage Database User task in Oracle SQL Developer."""

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


def verify_manage_database_user(traj, env_info, task_info):
    """
    Verify that REPORT_USER was created with correct privileges.

    Criteria (100 pts total):
    1. User exists and was newly created (15 pts)
    2. SELECT grants on all 3 HR tables (25 pts)
    3. User can actually query HR.EMPLOYEES (15 pts)
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
            copy_from_env("/tmp/manage_user_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        user_exists = result.get('user_exists', False)
        user_new = result.get('user_newly_created', False)
        grant_count = result.get('grant_count', 0)
        can_query = result.get('can_query', False)
        gui_evidence = result.get('gui_evidence', {})

        if not user_exists:
            return {
                "passed": False, "score": 0,
                "feedback": "FAILED: REPORT_USER does not exist",
                "subscores": {"user_created": False, "grants_correct": False,
                              "can_query": False, "gui_verified": False, "vlm_verified": False}
            }

        # Criterion 1: User exists and newly created (15 pts)
        if user_new:
            score += 15
            feedback_parts.append("REPORT_USER created during task")
            subscores['user_created'] = True
        else:
            score += 5
            feedback_parts.append("REPORT_USER exists but creation timing uncertain")
            subscores['user_created'] = False

        # Criterion 2: SELECT grants on HR tables (25 pts)
        if grant_count >= 3:
            score += 25
            feedback_parts.append(f"All 3 SELECT grants present")
            subscores['grants_correct'] = True
        elif grant_count == 2:
            score += 16
            feedback_parts.append(f"2/3 SELECT grants present")
            subscores['grants_correct'] = False
        elif grant_count == 1:
            score += 8
            feedback_parts.append(f"1/3 SELECT grants present")
            subscores['grants_correct'] = False
        else:
            feedback_parts.append("No SELECT grants on HR tables")
            subscores['grants_correct'] = False

        # Criterion 3: Can actually query (15 pts)
        if can_query:
            score += 15
            feedback_parts.append("REPORT_USER can successfully query HR.EMPLOYEES")
            subscores['can_query'] = True
        elif result.get('has_create_session', False):
            score += 5
            feedback_parts.append("CREATE SESSION granted but query failed")
            subscores['can_query'] = False
        else:
            feedback_parts.append("REPORT_USER cannot connect or query")
            subscores['can_query'] = False

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
                    1. Is there a SQL Worksheet with CREATE USER or GRANT statements visible?
                    2. Can you see user management or security-related SQL operations?
                    3. Are there any results showing successful execution of DDL/DCL statements?
                    4. Does the connection panel show a SYSTEM or DBA connection?
                    Respond with "VERIFIED" if user management operations are visible,
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
            feedback_parts.append("VLM: User management operations visible")
        elif user_exists and gui_used:
            score += 5
            feedback_parts.append("VLM: Not verified (but user + GUI validates)")
        else:
            feedback_parts.append("VLM: Not verified")

        passed = user_exists and grant_count >= 3 and can_query and gui_used and score >= 70

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
