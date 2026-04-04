#!/usr/bin/env python3
"""Verifier for Analytics Data Warehouse Build task."""

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


def verify_analytics_warehouse_build(traj, env_info, task_info):
    """
    Verify analytics data warehouse construction task.

    Scoring (100 pts total):
    1. Fact table created in ANALYTICS schema with data (25 pts)
    2. Required dimension tables exist (DIM_DEPARTMENT, DIM_JOB) (20 pts)
    3. Fact table contains >= 50 rows (15 pts)
    4. RPT_DEPT_SALARY_SUMMARY view exists and returns data (15 pts)
    5. GUI usage verified (25 pts)

    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/analytics_warehouse_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        fact_exists = result.get('fact_table_exists', False)
        fact_name = result.get('fact_table_name', '')
        fact_rows = result.get('fact_row_count', 0)
        dim_dept = result.get('dim_department_exists', False)
        dim_job = result.get('dim_job_exists', False)
        dim_count = result.get('dim_count', 0)
        view_exists = result.get('rpt_view_exists', False)
        view_rows = result.get('rpt_view_rows', 0)
        initial_fact = result.get('initial_fact_count', 0)
        initial_dim = result.get('initial_dim_count', 0)
        gui_evidence = result.get('gui_evidence', {})

        # Criterion 1: Fact table created (25 pts)
        fact_newly_created = fact_exists and (result.get('analytics_non_stg_table_count', 0) > initial_fact)
        if fact_exists and fact_name:
            score += 25
            feedback_parts.append(f"Fact table '{fact_name}' exists in ANALYTICS schema (25/25)")
            subscores['fact_table'] = True
        elif fact_exists:
            score += 20
            feedback_parts.append("A FACT_* table exists in ANALYTICS schema (20/25)")
            subscores['fact_table'] = True
        else:
            feedback_parts.append("No FACT_* table found in ANALYTICS schema (0/25)")
            subscores['fact_table'] = False

        # Criterion 2: Dimension tables (20 pts)
        dims_present = (1 if dim_dept else 0) + (1 if dim_job else 0)
        if dim_dept and dim_job:
            score += 20
            feedback_parts.append("Both DIM_DEPARTMENT and DIM_JOB exist (20/20)")
            subscores['dimensions'] = True
        elif dims_present == 1:
            score += 10
            missing = "DIM_DEPARTMENT" if not dim_dept else "DIM_JOB"
            feedback_parts.append(f"Only 1 of 2 required dimension tables found; missing {missing} (10/20)")
            subscores['dimensions'] = False
        elif dim_count >= 2:
            score += 8
            feedback_parts.append(f"{dim_count} DIM_* tables found but required DIM_DEPARTMENT/DIM_JOB missing (8/20)")
            subscores['dimensions'] = False
        else:
            feedback_parts.append("No dimension tables found in ANALYTICS schema (0/20)")
            subscores['dimensions'] = False

        # Criterion 3: Fact table data volume (15 pts)
        if fact_rows >= 100:
            score += 15
            feedback_parts.append(f"Fact table has {fact_rows} rows (excellent) (15/15)")
            subscores['fact_data'] = True
        elif fact_rows >= 50:
            score += 15
            feedback_parts.append(f"Fact table has {fact_rows} rows (meets minimum 50) (15/15)")
            subscores['fact_data'] = True
        elif fact_rows >= 10:
            score += 7
            feedback_parts.append(f"Fact table has only {fact_rows} rows (need >= 50) (7/15)")
            subscores['fact_data'] = False
        elif fact_exists:
            score += 2
            feedback_parts.append(f"Fact table is empty or has {fact_rows} rows (2/15)")
            subscores['fact_data'] = False
        else:
            subscores['fact_data'] = False

        # Criterion 4: RPT_DEPT_SALARY_SUMMARY view (15 pts)
        if view_exists and view_rows >= 5:
            score += 15
            feedback_parts.append(f"RPT_DEPT_SALARY_SUMMARY view returns {view_rows} rows (15/15)")
            subscores['summary_view'] = True
        elif view_exists:
            score += 8
            feedback_parts.append(f"RPT_DEPT_SALARY_SUMMARY exists but returns {view_rows} rows (8/15)")
            subscores['summary_view'] = False
        else:
            feedback_parts.append("RPT_DEPT_SALARY_SUMMARY view not found in ANALYTICS schema (0/15)")
            subscores['summary_view'] = False

        # Criterion 5: GUI usage (25 pts)
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

        # VLM bonus
        if query_vlm:
            try:
                temp_ss = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_ss.name)
                    vlm_prompt = (
                        "Examine this Oracle SQL Developer screenshot. "
                        "Is there SQL code visible that creates tables or views for a data warehouse "
                        "(e.g., CREATE TABLE FACT_, DIM_, star schema, analytics)? "
                        "Reply VERIFIED if warehouse/analytics SQL work is visible, else NOT_VERIFIED."
                    )
                    vlm_result = query_vlm(image=temp_ss.name, prompt=vlm_prompt)
                    if vlm_result and 'VERIFIED' in str(vlm_result).upper() and 'NOT_VERIFIED' not in str(vlm_result).upper():
                        if score < 95:
                            score = min(score + 5, 100)
                            feedback_parts.append("VLM: warehouse SQL work visible (+5 bonus)")
                finally:
                    os.unlink(temp_ss.name)
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")

        passed = (
            subscores.get('fact_table', False) and
            subscores.get('dimensions', False) and
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
