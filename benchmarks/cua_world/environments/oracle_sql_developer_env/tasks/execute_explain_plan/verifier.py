#!/usr/bin/env python3
"""Verifier for Execute Explain Plan task in Oracle SQL Developer."""

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


def verify_execute_explain_plan(traj, env_info, task_info):
    """
    Verify that an explain plan was generated for a complex query.

    Criteria (100 pts total):
    1. Output file exists with plan operations (15 pts)
    2. Query correctness - ranking function, departments, salary, top-N (20 pts)
    3. Plan shows JOIN operation (both tables referenced) (15 pts)
    4. Plan shows window function / advanced operations (10 pts)
    5. GUI usage verified (25 pts)
    6. VLM verification (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/explain_plan_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        output_exists = result.get('output_file_exists', False)
        has_plan = result.get('output_has_plan', False)
        has_join = result.get('plan_has_join', False)
        has_window = result.get('plan_has_window', False)
        tables_found = result.get('plan_tables_found', '')
        gui_evidence = result.get('gui_evidence', {})

        # Query correctness fields
        query_has_rank = result.get('query_has_rank', False)
        query_has_department = result.get('query_has_department', False)
        query_has_salary = result.get('query_has_salary', False)
        query_has_top_n = result.get('query_has_top_n', False)

        if not output_exists:
            return {
                "passed": False, "score": 0,
                "feedback": "FAILED: Explain plan output file not found at /home/ga/Documents/exports/explain_plan_output.txt",
                "subscores": {"output_file": False, "query_correct": False,
                              "plan_quality": False, "advanced_ops": False,
                              "gui_verified": False, "vlm_verified": False}
            }

        # Criterion 1: Output file with plan operations (15 pts)
        if has_plan:
            score += 15
            feedback_parts.append("Explain plan output contains execution plan operations")
            subscores['output_file'] = True
        else:
            score += 3
            feedback_parts.append("Output file exists but doesn't contain recognizable plan operations")
            subscores['output_file'] = False

        # Criterion 2: Query correctness (20 pts)
        # Check that the SQL query has the right elements: ranking, departments, salary, top-N
        query_signals = sum([query_has_rank, query_has_department, query_has_salary, query_has_top_n])
        query_correct = query_signals >= 3
        if query_signals >= 4:
            score += 20
            feedback_parts.append("Query correct: has ranking function, departments, salary, top-N filter")
            subscores['query_correct'] = True
        elif query_signals >= 3:
            score += 15
            feedback_parts.append(f"Query mostly correct ({query_signals}/4 elements: "
                                  f"rank={query_has_rank}, dept={query_has_department}, "
                                  f"salary={query_has_salary}, topN={query_has_top_n})")
            subscores['query_correct'] = True
        elif query_signals >= 2:
            score += 8
            feedback_parts.append(f"Query partially correct ({query_signals}/4 elements)")
            subscores['query_correct'] = False
        elif query_signals >= 1:
            score += 3
            feedback_parts.append(f"Query has only {query_signals}/4 required elements")
            subscores['query_correct'] = False
        else:
            feedback_parts.append("Query text not found or missing all required elements")
            subscores['query_correct'] = False

        # Criterion 3: Plan shows JOIN with both tables (15 pts)
        both_tables = 'EMPLOYEES' in tables_found and 'DEPARTMENTS' in tables_found
        if has_join and both_tables:
            score += 15
            feedback_parts.append(f"Plan shows JOIN on {tables_found}")
            subscores['plan_quality'] = True
        elif has_join:
            score += 8
            feedback_parts.append(f"Plan has JOIN but tables: {tables_found}")
            subscores['plan_quality'] = False
        elif both_tables:
            score += 5
            feedback_parts.append("Both tables referenced but no JOIN detected")
            subscores['plan_quality'] = False
        else:
            feedback_parts.append("Plan missing JOIN or table references")
            subscores['plan_quality'] = False

        # Criterion 4: Window function / advanced operations (10 pts)
        if has_window:
            score += 10
            feedback_parts.append("Window function (RANK/DENSE_RANK) detected in plan")
            subscores['advanced_ops'] = True
        elif result.get('plan_has_sort', False):
            score += 5
            feedback_parts.append("SORT operation found (but no window function)")
            subscores['advanced_ops'] = False
        else:
            feedback_parts.append("No window function or advanced operations in plan")
            subscores['advanced_ops'] = False

        # Criterion 5: GUI usage verified (25 pts)
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

        # Criterion 6: VLM verification (15 pts)
        vlm_verified = False
        if query_vlm:
            try:
                temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
                    vlm_prompt = """Analyze this screenshot of Oracle SQL Developer.
                    Questions:
                    1. Is there an Explain Plan tab or panel visible?
                    2. Can you see execution plan tree with operations like TABLE ACCESS, HASH JOIN?
                    3. Is there a SQL query visible in a worksheet?
                    4. Does the plan show cost or cardinality estimates?
                    Respond with "VERIFIED" if explain plan results are visible,
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
            score += 15
            feedback_parts.append("VLM: Explain plan visible")
        elif has_plan and gui_used:
            score += 3
            feedback_parts.append("VLM: Not verified (but plan + GUI validates)")
        else:
            feedback_parts.append("VLM: Not verified")

        passed = has_plan and query_correct and gui_used and score >= 70

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
