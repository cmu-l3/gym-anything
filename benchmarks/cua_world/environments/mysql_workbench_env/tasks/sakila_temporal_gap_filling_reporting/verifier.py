#!/usr/bin/env python3
"""
Verifier for Sakila Temporal Gap Filling & Moving Averages task.

Scoring Breakdown (100 pts):
1. Continuous Timeline (30 pts): Main CSV has 31 rows (full July coverage).
2. Gap Filling (25 pts): The specific gap dates (July 4, 15) are present in output with 0 revenue.
3. Moving Average (20 pts): Column exists in view/CSV.
4. Views Created (15 pts): Database views exist (proof of structural solution).
5. Outage Report (10 pts): Secondary CSV identifies zero-revenue days.

Pass Threshold: 65 points.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_sakila_temporal_gap_filling_reporting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/gap_analysis_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script failed."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Continuous Timeline (30 pts)
    # Check if main CSV has exactly 31 rows (July has 31 days)
    # Allow loose matching on View count if CSV is missing but view is perfect
    main_csv_rows = result.get('main_csv_rows', 0)
    view_rows = result.get('view_row_count', 0)
    
    if main_csv_rows == 31:
        score += 30
        feedback_parts.append("Timeline continuous (31 rows in CSV) [30/30]")
    elif view_rows == 31:
        # Partial credit if view is correct but export failed/wrong format
        score += 20
        feedback_parts.append("View has 31 rows, but CSV row count mismatch [20/30]")
    elif main_csv_rows > 25:
        score += 10
        feedback_parts.append(f"Timeline incomplete or extra rows ({main_csv_rows} rows) [10/30]")
    else:
        feedback_parts.append(f"Timeline missing or incorrect ({main_csv_rows} rows) [0/30]")

    # 2. Gap Filling (25 pts)
    # Check if the specific gap dates exist and have 0 revenue
    # Primary signal: View logic check from export script
    gap_dates_view = result.get('gap_dates_present_in_view', 0)
    gap_revenue_zero = result.get('gap_revenue_is_zero', 0)
    gap_dates_csv = result.get('gap_dates_in_csv', 0)
    
    if gap_dates_view == 2 and gap_revenue_zero == 1:
        score += 25
        feedback_parts.append("Gap filling verified in database view [25/25]")
    elif gap_dates_csv == 1:
        # Fallback to CSV grep check
        score += 25
        feedback_parts.append("Gap dates found in CSV [25/25]")
    else:
        feedback_parts.append("Gap dates (July 4, 15) missing or have non-zero revenue [0/25]")

    # 3. Moving Average (20 pts)
    # Check if column exists
    has_avg = result.get('has_moving_avg_col', 0)
    if has_avg:
        score += 20
        feedback_parts.append("Moving average column present [20/20]")
    else:
        feedback_parts.append("Moving average column missing [0/20]")

    # 4. Views Created (15 pts)
    # Check if views exist
    cal_view = result.get('calendar_view_exists', 0)
    ana_view = result.get('analysis_view_exists', 0)
    
    if cal_view and ana_view:
        score += 15
        feedback_parts.append("Both required views created [15/15]")
    elif ana_view:
        score += 10
        feedback_parts.append("Analysis view created [10/15]")
    else:
        feedback_parts.append("Views not created [0/15]")

    # 5. Outage Report (10 pts)
    zero_csv_exists = result.get('zero_csv_exists', False)
    zero_csv_correct = result.get('zero_csv_correct_content', 0)
    
    if zero_csv_exists and zero_csv_correct:
        score += 10
        feedback_parts.append("Outage report correct [10/10]")
    elif zero_csv_exists:
        score += 5
        feedback_parts.append("Outage report exists but content incorrect [5/10]")
    else:
        feedback_parts.append("Outage report missing [0/10]")

    # Final Check
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }