#!/usr/bin/env python3
"""Verifier for Create Oracle Connection task in Oracle SQL Developer."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_gui_usage(gui_evidence):
    """Check if SQL Developer GUI was actually used (not just command-line tools).

    Returns (gui_used: bool, gui_score: float 0-1, details: str)
    """
    if not gui_evidence:
        return False, 0.0, "No GUI evidence collected"

    signals = 0
    total_signals = 4
    details = []

    # MRU connection cache proves GUI connection was used
    mru = gui_evidence.get('mru_connection_count', 0)
    if mru > 0:
        signals += 1
        details.append(f"MRU cache has {mru} connections")

    # Window title changed from Welcome Page proves GUI interaction
    if gui_evidence.get('window_title_changed', False):
        signals += 1
        details.append(f"Window title: {gui_evidence.get('window_title', '')}")

    # Active SQL Developer Oracle sessions prove GUI-initiated DB connection
    sessions = gui_evidence.get('sqldev_oracle_sessions', 0)
    if sessions > 0:
        signals += 1
        details.append(f"{sessions} active SQL Developer DB sessions")

    # SQL history entries prove GUI worksheet usage
    history = gui_evidence.get('sql_history_count', 0)
    if history > 0:
        signals += 1
        details.append(f"{history} SQL history entries")

    gui_used = signals >= 2
    gui_score = min(signals / total_signals, 1.0)
    detail_str = "; ".join(details) if details else "No GUI interaction detected"
    return gui_used, gui_score, detail_str


def verify_create_oracle_connection(traj, env_info, task_info):
    """
    Verify that an Oracle database connection was created in SQL Developer.

    Criteria (100 pts total):
    1. Connection created via GUI with correct name (25 pts)
    2. Oracle database accessible with HR schema (20 pts)
    3. New connection was created during the task (20 pts)
    4. GUI usage verified (20 pts)
    5. VLM verification of connection panel (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')
    metadata = task_info.get('metadata', {})
    expected_connection_name = metadata.get('expected_connection_name', 'HR Database')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/connection_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        connection_created = result.get('connection_created', False)
        connection_name = result.get('connection_name_found', '')
        oracle_accessible = result.get('oracle_accessible', False)
        hr_tables_exist = result.get('hr_tables_exist', False)
        new_connections = result.get('new_connections', 0)
        gui_evidence = result.get('gui_evidence', {})

        logger.info(f"Result: conn={connection_created}, name={connection_name}, "
                    f"oracle={oracle_accessible}, new={new_connections}, gui={gui_evidence}")

        # Criterion 1: Connection created with correct name (25 pts)
        if connection_created and connection_name:
            if connection_name.lower().strip() == expected_connection_name.lower().strip():
                score += 25
                feedback_parts.append(f"Connection '{connection_name}' matches expected name")
                subscores['connection_name_correct'] = True
            else:
                score += 10
                feedback_parts.append(f"Connection '{connection_name}' created but expected '{expected_connection_name}'")
                subscores['connection_name_correct'] = False
        elif connection_created:
            score += 5
            feedback_parts.append("Connection created but name not detected")
            subscores['connection_name_correct'] = False
        else:
            feedback_parts.append("No Oracle connection configuration detected")
            subscores['connection_name_correct'] = False

        # Criterion 2: Oracle accessible with HR schema (20 pts)
        if oracle_accessible and hr_tables_exist:
            score += 20
            feedback_parts.append(f"Oracle HR schema accessible ({result.get('employee_count', 0)} employees)")
            subscores['oracle_accessible'] = True
        elif oracle_accessible:
            score += 10
            feedback_parts.append("Oracle accessible but HR tables not verified")
            subscores['oracle_accessible'] = True
        else:
            feedback_parts.append("Oracle database not accessible")
            subscores['oracle_accessible'] = False

        # Criterion 3: New connection created during task (20 pts)
        if new_connections > 0:
            score += 20
            feedback_parts.append(f"New connection created during task ({new_connections} new)")
            subscores['new_connection'] = True
        elif connection_created:
            score += 5
            feedback_parts.append("Connection exists but creation timing not verified")
            subscores['new_connection'] = False
        else:
            feedback_parts.append("No new connection detected")
            subscores['new_connection'] = False

        # Criterion 4: GUI usage verified (20 pts) - CRITICAL
        gui_used, gui_score_frac, gui_details = _check_gui_usage(gui_evidence)
        gui_pts = int(gui_score_frac * 20)
        score += gui_pts
        subscores['gui_verified'] = gui_used
        if gui_used:
            feedback_parts.append(f"GUI usage confirmed ({gui_details})")
        elif gui_pts > 0:
            feedback_parts.append(f"Partial GUI evidence ({gui_details})")
        else:
            feedback_parts.append("No GUI usage evidence - task may have been done via command line")

        # Criterion 5: VLM verification (15 pts)
        vlm_verified = False
        if query_vlm:
            try:
                temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
                    vlm_prompt = """Analyze this screenshot of Oracle SQL Developer.
                    Questions:
                    1. Is the Connections panel visible on the left side?
                    2. Can you see a database connection entry (possibly named 'HR Database' or similar)?
                    3. Is the connection expanded showing tables like EMPLOYEES, DEPARTMENTS?
                    4. Does the interface show a successfully connected Oracle database?
                    Respond with "VERIFIED" if you can see a configured Oracle connection,
                    or "NOT VERIFIED" if no connection is visible."""
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
            score += 15
            feedback_parts.append("VLM: Connection panel verified")
        elif connection_created and gui_used:
            score += 5
            feedback_parts.append("VLM: Not verified (but connection config + GUI validates)")
        else:
            feedback_parts.append("VLM: Not verified")

        passed = (connection_created and new_connections > 0 and gui_used and score >= 70)

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
