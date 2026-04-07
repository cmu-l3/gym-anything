#!/usr/bin/env python3
"""
Verifier for Sakila Window Analytics Reporting task.
Checks database objects (views, tables, procedures) and exported CSV files.
"""

import json
import logging
import os
import tempfile
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_window_analytics_reporting(traj, env_info, task_info):
    """
    Verify the Sakila BI task.
    
    Score breakdown (100 pts):
    1. View `v_film_revenue_ranked` exists & correct structure: 20 pts
    2. View `v_film_revenue_ranked` logic (valid ranks): 5 pts
    3. View `v_customer_rfm` exists & correct structure: 20 pts
    4. View `v_customer_rfm` logic (NTILEs 1-4): 5 pts
    5. Table `rpt_monthly_category_performance` exists & populated: 15 pts
    6. Table logic (percentages sum to ~100): 5 pts
    7. Procedure `sp_refresh_category_performance` exists: 10 pts
    8. CSV exports created and populated: 20 pts (10 each)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Verify v_film_revenue_ranked (20 + 5 pts)
    v1 = result.get("view_film_revenue", {})
    if v1.get("exists") and v1.get("cols_match_count", 0) >= 4:
        score += 20
        feedback.append("View v_film_revenue_ranked created correctly (+20)")
        
        # Check logic: Are there multiple categories with rank 1? 
        # (Should be ~16 categories, so at least 10 is a safe check for correct PARTITION BY)
        if v1.get("valid_ranks_count", 0) >= 10:
            score += 5
            feedback.append("Rank logic (PARTITION BY) correct (+5)")
        else:
            feedback.append(f"Rank logic questionable: Only {v1.get('valid_ranks_count')} categories have a #1 rank")
    else:
        feedback.append("View v_film_revenue_ranked missing or incomplete columns")

    # 2. Verify v_customer_rfm (20 + 5 pts)
    v2 = result.get("view_customer_rfm", {})
    if v2.get("exists") and v2.get("cols_match_count", 0) >= 3:
        score += 20
        feedback.append("View v_customer_rfm created correctly (+20)")
        
        # Check logic: Are all scores between 1 and 4? (Count of bad rows should be 0)
        # Also ensure rows exist
        if v2.get("row_count", 0) > 0 and v2.get("invalid_scores_count", 999) == 0:
            score += 5
            feedback.append("RFM NTILE logic correct (+5)")
        else:
            feedback.append("RFM logic invalid (scores outside 1-4 or no data)")
    else:
        feedback.append("View v_customer_rfm missing or incomplete")

    # 3. Verify Reporting Table (15 + 5 pts)
    tbl = result.get("table_rpt", {})
    if tbl.get("exists") and tbl.get("row_count", 0) > 20:
        score += 15
        feedback.append("Reporting table exists and populated (+15)")
        
        # Check percentage calculation (sum of pct per month should be ~100)
        # bad_pct_months_count counts months where sum is not 98-102
        if tbl.get("bad_pct_months_count", 999) == 0:
            score += 5
            feedback.append("Percentage calculation logic correct (+5)")
        else:
            feedback.append("Percentage calculation incorrect (sums don't approximate 100%)")
    else:
        feedback.append("Reporting table missing or empty")

    # 4. Verify Procedure (10 pts)
    if result.get("proc_refresh", {}).get("exists"):
        score += 10
        feedback.append("Stored Procedure created (+10)")
    else:
        feedback.append("Stored Procedure missing")

    # 5. Verify CSV Exports (10 + 10 pts)
    csv1 = result.get("csv_film_revenue", {})
    if csv1.get("exists") and csv1.get("new") and csv1.get("lines", 0) > 100:
        score += 10
        feedback.append("Film revenue CSV exported (+10)")
    else:
        feedback.append("Film revenue CSV missing or stale")

    csv2 = result.get("csv_monthly_perf", {})
    if csv2.get("exists") and csv2.get("new") and csv2.get("lines", 0) > 10:
        score += 10
        feedback.append("Monthly performance CSV exported (+10)")
    else:
        feedback.append("Monthly performance CSV missing or stale")

    # Final result
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }