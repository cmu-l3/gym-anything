#!/usr/bin/env python3
"""
Verifier for sakila_crosstab_rental_reports task.

Checks:
1. Three views exist in Sakila database.
2. Views have correct column names (crosstab structure).
3. Views return expected row counts (data integrity).
4. CSV export files exist, were created during task, and have content.

Scoring:
- v_rental_by_day_category (25 pts)
- v_monthly_rental_trend (25 pts)
- v_rating_revenue_matrix (25 pts)
- CSV Exports (25 pts)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_crosstab_rental_reports(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # 1. Verify v_rental_by_day_category (25 pts)
    # ---------------------------------------------------------
    v1 = result.get('views', {}).get('v_rental_by_day_category', {})
    if v1.get('exists') == 1:
        score += 5
        feedback.append("v_rental_by_day_category created (+5)")
        
        # Check columns
        expected_cols = ["category", "sun_rentals", "mon_rentals", "tue_rentals", "wed_rentals", "thu_rentals", "fri_rentals", "sat_rentals", "total_rentals"]
        actual_cols = v1.get('columns', '').split(',')
        if all(col in actual_cols for col in expected_cols):
            score += 10
            feedback.append("v_rental_by_day_category columns correct (+10)")
        else:
            feedback.append(f"v_rental_by_day_category missing columns. Found: {actual_cols}")

        # Check rows (16 categories)
        if v1.get('row_count', 0) == 16:
            score += 10
            feedback.append("v_rental_by_day_category row count correct (16) (+10)")
        else:
            feedback.append(f"v_rental_by_day_category row count incorrect: {v1.get('row_count')}")
    else:
        feedback.append("v_rental_by_day_category view missing")

    # ---------------------------------------------------------
    # 2. Verify v_monthly_rental_trend (25 pts)
    # ---------------------------------------------------------
    v2 = result.get('views', {}).get('v_monthly_rental_trend', {})
    if v2.get('exists') == 1:
        score += 5
        feedback.append("v_monthly_rental_trend created (+5)")
        
        expected_cols = ["rental_month", "store_1_rentals", "store_2_rentals", "total_rentals"]
        actual_cols = v2.get('columns', '').split(',')
        if all(col in actual_cols for col in expected_cols):
            score += 10
            feedback.append("v_monthly_rental_trend columns correct (+10)")
        else:
            feedback.append(f"v_monthly_rental_trend missing columns. Found: {actual_cols}")

        # Check rows (should be at least 5 months with data in 2005)
        if v2.get('row_count', 0) >= 5:
            score += 10
            feedback.append("v_monthly_rental_trend row count reasonable (+10)")
        else:
            feedback.append(f"v_monthly_rental_trend row count suspicious: {v2.get('row_count')}")
    else:
        feedback.append("v_monthly_rental_trend view missing")

    # ---------------------------------------------------------
    # 3. Verify v_rating_revenue_matrix (25 pts)
    # ---------------------------------------------------------
    v3 = result.get('views', {}).get('v_rating_revenue_matrix', {})
    if v3.get('exists') == 1:
        score += 5
        feedback.append("v_rating_revenue_matrix created (+5)")
        
        expected_cols = ["rating", "q1_revenue", "q2_revenue", "q3_revenue", "q4_revenue", "total_revenue"]
        actual_cols = v3.get('columns', '').split(',')
        if all(col in actual_cols for col in expected_cols):
            score += 10
            feedback.append("v_rating_revenue_matrix columns correct (+10)")
        else:
            feedback.append(f"v_rating_revenue_matrix missing columns. Found: {actual_cols}")

        # Check rows (5 ratings)
        if v3.get('row_count', 0) == 5:
            score += 10
            feedback.append("v_rating_revenue_matrix row count correct (5) (+10)")
        else:
            feedback.append(f"v_rating_revenue_matrix row count incorrect: {v3.get('row_count')}")
    else:
        feedback.append("v_rating_revenue_matrix view missing")

    # ---------------------------------------------------------
    # 4. Verify CSV Exports (25 pts)
    # ---------------------------------------------------------
    files = result.get('files', {})
    
    # File 1: rental_by_day_category.csv (13 pts)
    f1 = files.get('rental_by_day_category.csv', {})
    if f1.get('exists') and f1.get('created_during_task'):
        if f1.get('lines', 0) >= 16:
            score += 13
            feedback.append("rental_by_day_category.csv exported correctly (+13)")
        else:
            score += 5
            feedback.append("rental_by_day_category.csv exists but incomplete (+5)")
    else:
        feedback.append("rental_by_day_category.csv missing or old")

    # File 2: rating_revenue_matrix.csv (12 pts)
    f2 = files.get('rating_revenue_matrix.csv', {})
    if f2.get('exists') and f2.get('created_during_task'):
        if f2.get('lines', 0) >= 5:
            score += 12
            feedback.append("rating_revenue_matrix.csv exported correctly (+12)")
        else:
            score += 5
            feedback.append("rating_revenue_matrix.csv exists but incomplete (+5)")
    else:
        feedback.append("rating_revenue_matrix.csv missing or old")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "; ".join(feedback)
    }