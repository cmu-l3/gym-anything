#!/usr/bin/env python3
"""
Verifier for chinook_dashboard_views task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_dashboard_views(traj, env_info, task_info):
    """
    Verify creation of SQL views, script, and CSV exports.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Criterion 1: DBeaver Connection (5 pts) ---
    if result.get("db_connection_exists"):
        score += 5
        feedback.append("DBeaver connection 'Chinook' found.")
    else:
        feedback.append("DBeaver connection 'Chinook' NOT found.")

    # --- Criterion 2: Database Views (45 pts) ---
    views = result.get("views", {})
    
    # v_customer_spending
    cust = views.get("v_customer_spending", {})
    if cust.get("exists"):
        score += 5
        # Check rows (should be 59)
        if cust.get("row_count") == 59:
            score += 5
        else:
            feedback.append(f"v_customer_spending has {cust.get('row_count')} rows (expected 59).")
        
        # Check logic via top spender check
        # Expected: Helena Holý | 49.62 (or similar depending on sort)
        top_raw = cust.get("top_spender_raw", "")
        if top_raw and "|" in top_raw:
            try:
                val = float(top_raw.split("|")[1])
                if 40 < val < 60: # Rough range check
                    score += 5
                else:
                    feedback.append(f"v_customer_spending top value {val} out of range.")
            except:
                pass
    else:
        feedback.append("View v_customer_spending NOT created.")

    # v_genre_revenue
    genre = views.get("v_genre_revenue", {})
    if genre.get("exists"):
        score += 5
        # Check rows (should be 25)
        if genre.get("row_count") == 25:
            score += 5
        else:
            feedback.append(f"v_genre_revenue has {genre.get('row_count')} rows (expected 25).")
        
        # Check top genre (Rock)
        if "Rock" in genre.get("top_genre", ""):
            score += 5
        else:
            feedback.append(f"v_genre_revenue top genre is {genre.get('top_genre')} (expected Rock).")
    else:
        feedback.append("View v_genre_revenue NOT created.")

    # v_employee_sales_summary
    emp = views.get("v_employee_sales_summary", {})
    if emp.get("exists"):
        score += 5
        # Check rows (should be 3)
        if emp.get("row_count") == 3:
            score += 5
        else:
            feedback.append(f"v_employee_sales_summary has {emp.get('row_count')} rows (expected 3).")
        
        # Check revenue sum (Approx 2328.60)
        rev_sum = emp.get("total_revenue_sum", 0)
        try:
            if 2320 <= float(rev_sum) <= 2340:
                score += 5
            else:
                feedback.append(f"v_employee_sales_summary total revenue sum {rev_sum} incorrect.")
        except:
             feedback.append("Could not parse employee revenue sum.")
    else:
        feedback.append("View v_employee_sales_summary NOT created.")

    # --- Criterion 3: Files Created (50 pts) ---
    files = result.get("files", {})

    # SQL Script (10 pts)
    script = files.get("sql_script", {})
    if script.get("exists") and script.get("size") > 100:
        score += 10
        if not script.get("created_during_task"):
            score -= 5 # Penalty for old file
            feedback.append("SQL script file timestamp is old.")
    else:
        feedback.append("SQL script missing or empty.")

    # CSVs (10 pts each + 5 for timestamp/size check = 15ish)
    # Simplified: 10 pts for existence + reasonable size > 50 bytes
    
    # Customer CSV
    f_cust = files.get("csv_customer", {})
    if f_cust.get("exists") and f_cust.get("size") > 100:
        score += 10
    else:
        feedback.append("customer_spending.csv missing/empty.")

    # Genre CSV
    f_genre = files.get("csv_genre", {})
    if f_genre.get("exists") and f_genre.get("size") > 50:
        score += 10
    else:
        feedback.append("genre_revenue.csv missing/empty.")

    # Employee CSV
    f_emp = files.get("csv_employee", {})
    if f_emp.get("exists") and f_emp.get("size") > 50:
        score += 10
    else:
        feedback.append("employee_sales.csv missing/empty.")
        
    # Anti-gaming: Ensure at least some views exist
    if not (views.get("v_customer_spending", {}).get("exists") or 
            views.get("v_genre_revenue", {}).get("exists")):
        return {"passed": False, "score": 0, "feedback": "No views were created in the database."}

    # Final Pass Logic
    # Threshold: 60, but must have created views and files
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }