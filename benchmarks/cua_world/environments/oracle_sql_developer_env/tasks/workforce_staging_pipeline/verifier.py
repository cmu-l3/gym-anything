#!/usr/bin/env python3
"""Verifier for Workforce Planning Staging Pipeline task."""

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
    if gui_evidence.get('window_title_changed', False):
        signals += 1
        details.append("window_title")
    gui_used = signals >= 2
    return gui_used, min(signals / 3, 1.0), "; ".join(details) or "No signals"

def verify_workforce_staging_pipeline(traj, env_info, task_info):
    """
    Verify workforce planning staging pipeline completion.
    
    Scoring (100 pts total):
    1. Table Existence & Columns (20 pts):
       - Table exists (10 pts)
       - Columns >= 14 (10 pts)
    2. Data Population & Joins (20 pts):
       - Exact row count = 107 (15 pts) (proves LEFT OUTER JOIN usage)
       - Null full_names = 0 (5 pts)
    3. Computed Fields (20 pts):
       - salary_quartile min=1, max=4 (10 pts)
       - tenure_years >= 0 and previous_jobs >= 0 (10 pts)
    4. Index & View (20 pts):
       - Composite index exists and has 2 columns (10 pts)
       - View exists and returns > 0 rows (10 pts)
    5. CSV Export & GUI (20 pts):
       - CSV file exists, size > 1000 bytes, ~108 lines (10 pts)
       - GUI usage detected (10 pts)
       
    Pass condition: Score >= 60 AND Table exists AND Row count > 100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Extract variables
        table_exists = result.get('table_exists', False)
        col_count = result.get('col_count', 0)
        row_count = result.get('row_count', 0)
        quart_min = result.get('quart_min', 0)
        quart_max = result.get('quart_max', 0)
        tenure_neg_count = result.get('tenure_neg_count', 99)
        prev_jobs_neg_count = result.get('prev_jobs_neg_count', 99)
        null_names_count = result.get('null_names_count', 99)
        index_exists = result.get('index_exists', False)
        index_col_count = result.get('index_col_count', 0)
        view_exists = result.get('view_exists', False)
        view_rows = result.get('view_rows', 0)
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size', 0)
        csv_lines = result.get('csv_lines', 0)
        
        # 1. Table Existence & Columns (20 pts)
        if table_exists:
            score += 10
            feedback_parts.append("Table WORKFORCE_STAGING exists (10/10)")
            
            if col_count >= 14:  # Allowing minor missing column but mostly correct
                score += 10
                feedback_parts.append(f"Table has {col_count} columns (10/10)")
            elif col_count > 0:
                score += 5
                feedback_parts.append(f"Table has only {col_count} columns (5/10)")
        else:
            feedback_parts.append("Table WORKFORCE_STAGING does NOT exist (0/20)")
            
        # 2. Data Population & Joins (20 pts)
        if row_count == 107:
            score += 15
            feedback_parts.append("Correct row count (107) indicating proper LEFT OUTER JOINs (15/15)")
        elif row_count > 0:
            score += 8
            feedback_parts.append(f"Row count is {row_count} instead of 107 (likely missing outer joins) (8/15)")
            
        if row_count > 0 and null_names_count == 0:
            score += 5
            feedback_parts.append("No null full names (5/5)")
        elif null_names_count > 0 and null_names_count != 99:
            feedback_parts.append(f"Found {null_names_count} rows with missing full names (0/5)")
            
        # 3. Computed Fields (20 pts)
        if row_count > 0:
            if quart_min == 1 and quart_max == 4:
                score += 10
                feedback_parts.append("Salary quartiles calculated correctly (1-4) (10/10)")
            else:
                feedback_parts.append(f"Salary quartiles incorrect (min:{quart_min}, max:{quart_max}) (0/10)")
                
            if tenure_neg_count == 0 and prev_jobs_neg_count == 0:
                score += 10
                feedback_parts.append("Tenure and previous jobs computed validly (>=0) (10/10)")
            else:
                feedback_parts.append("Negative values found in tenure or previous jobs (0/10)")

        # 4. Index & View (20 pts)
        if index_exists and index_col_count == 2:
            score += 10
            feedback_parts.append("Composite index IDX_WS_DEPT_QUARTILE exists with 2 columns (10/10)")
        elif index_exists:
            score += 5
            feedback_parts.append(f"Index exists but has {index_col_count} matching columns instead of 2 (5/10)")
        else:
            feedback_parts.append("Index IDX_WS_DEPT_QUARTILE not found (0/10)")
            
        if view_exists and view_rows > 0:
            score += 10
            feedback_parts.append(f"View WORKFORCE_SUMMARY_VW exists and returns {view_rows} rows (10/10)")
        elif view_exists:
            score += 5
            feedback_parts.append("View exists but returns no data (5/10)")
        else:
            feedback_parts.append("View WORKFORCE_SUMMARY_VW not found (0/10)")

        # 5. CSV Export & GUI (20 pts)
        if csv_exists and csv_size > 1000 and (105 <= csv_lines <= 110):
            score += 10
            feedback_parts.append(f"CSV exported successfully ({csv_lines} lines, {csv_size} bytes) (10/10)")
        elif csv_exists:
            score += 5
            feedback_parts.append(f"CSV exists but size/lines anomalous ({csv_lines} lines) (5/10)")
        else:
            feedback_parts.append("CSV file not found (0/10)")
            
        gui_used, gui_score_frac, gui_details = _check_gui_usage({k: v for k, v in result.items() if isinstance(v, (int, bool))})
        gui_pts = int(10 * gui_score_frac)
        score += gui_pts
        if gui_pts > 0:
            feedback_parts.append(f"GUI usage detected [{gui_details}] ({gui_pts}/10)")
        else:
            feedback_parts.append("No GUI usage evidence (0/10)")

        # Determine pass/fail
        passed = (score >= 60) and table_exists and (row_count >= 100)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed with internal error: {e}"
        }