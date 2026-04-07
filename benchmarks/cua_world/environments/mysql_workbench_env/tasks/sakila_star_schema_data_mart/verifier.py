#!/usr/bin/env python3
"""
Verifier for sakila_star_schema_data_mart task.
Checks the structure and content of the created data mart and the exported CSV.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_mart(traj, env_info, task_info):
    """
    Verify the Sakila Star Schema Data Mart task.
    
    Scoring Rubric (100 pts total):
    - Database creation: 5 pts
    - Dim Date: Structure (5), Populated ~731 rows (10)
    - Dim Customer: Structure (5), Populated ~599 rows (10)
    - Dim Film: Structure (5), Populated ~1000 rows (10)
    - Dim Store: Structure (3), Populated 2 rows (2)
    - Fact Rental: Structure (5), Populated ~16000 rows (15)
    - View: Exists (5), Logic/Data correct (10)
    - CSV: Exists & populated (5), Timestamp valid (5)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Database Check (5 pts)
    if result.get('db_exists'):
        score += 5
        feedback.append("Database 'sakila_mart' created.")
    else:
        feedback.append("Database 'sakila_mart' NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Dim Date Check (15 pts)
    # Structure (>=9 cols)
    if result.get('dim_date_cols', 0) >= 9:
        score += 5
    else:
        feedback.append(f"dim_date has incorrect columns ({result.get('dim_date_cols')}).")
    
    # Data (731 rows for 2005-2006)
    rows = result.get('dim_date_rows', 0)
    if 730 <= rows <= 732:
        score += 10
    elif rows > 0:
        score += 5
        feedback.append(f"dim_date has {rows} rows (expected ~731).")
    else:
        feedback.append("dim_date is empty.")

    # 3. Dim Customer Check (15 pts)
    # Structure (>=8 cols)
    if result.get('dim_cust_cols', 0) >= 8:
        score += 5
    else:
        feedback.append("dim_customer missing columns.")
    
    # Data (599 rows)
    rows = result.get('dim_cust_rows', 0)
    if rows == 599:
        score += 10
    elif rows > 500:
        score += 5
        feedback.append(f"dim_customer has {rows} rows (expected 599).")
    else:
        feedback.append("dim_customer data missing or incomplete.")

    # 4. Dim Film Check (15 pts)
    # Structure (>=9 cols)
    if result.get('dim_film_cols', 0) >= 9:
        score += 5
    else:
        feedback.append("dim_film missing columns.")
    
    # Data (~1000 rows)
    rows = result.get('dim_film_rows', 0)
    if rows >= 950:
        score += 10
    elif rows > 0:
        score += 5
        feedback.append(f"dim_film has {rows} rows (expected ~1000).")
    else:
        feedback.append("dim_film is empty.")

    # 5. Dim Store Check (5 pts)
    # Structure (>=7 cols)
    if result.get('dim_store_cols', 0) >= 7:
        score += 3
    else:
        feedback.append("dim_store missing columns.")
    
    # Data (2 rows)
    rows = result.get('dim_store_rows', 0)
    if rows == 2:
        score += 2
    else:
        feedback.append(f"dim_store has {rows} rows (expected 2).")

    # 6. Fact Rental Check (20 pts)
    # Structure (>=6 cols)
    if result.get('fact_rental_cols', 0) >= 6:
        score += 5
    else:
        feedback.append("fact_rental missing columns.")
    
    # Data (~16044 rows)
    rows = result.get('fact_rental_rows', 0)
    if rows >= 15000:
        score += 15
    elif rows > 1000:
        score += 5
        feedback.append(f"fact_rental has {rows} rows (expected >15000).")
    else:
        feedback.append("fact_rental is effectively empty.")

    # 7. View Check (15 pts)
    if result.get('view_exists'):
        score += 5
        # Logic check: returns rows and has revenue
        if result.get('view_rows', 0) >= 10 and float(result.get('view_revenue_sum', 0)) > 0:
            score += 10
            feedback.append("View logic verified (returns data with revenue).")
        else:
            feedback.append("View exists but returns no meaningful data.")
    else:
        feedback.append("View 'v_monthly_store_performance' NOT found.")

    # 8. CSV Export Check (10 pts)
    if result.get('csv_exists') and result.get('csv_rows', 0) >= 10:
        score += 5
        if result.get('file_created_during_task'):
            score += 5
        else:
            feedback.append("CSV file timestamp indicates it was not created during this task.")
    else:
        feedback.append("CSV export missing or empty.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }