#!/usr/bin/env python3
"""
Verifier for dynamic_stockout_prediction_model task.
"""
import json
import logging
import os
import tempfile
import math

logger = logging.getLogger(__name__)

def verify_stockout_prediction(traj, env_info, task_info):
    """
    Verifies the SQL View, Stored Procedure, and CSV Export.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 2. Check View (30 pts)
    if result.get("view_exists"):
        score += 10
        feedback.append("View created.")
        if result.get("has_required_cols"):
            score += 10
            feedback.append("Required columns present.")
        else:
            feedback.append("Missing required columns in view.")
    else:
        feedback.append("View Production.vw_ProductStockoutProjection NOT found.")

    # 3. Logic Validation (Spot Check) (25 pts)
    spot = result.get("spot_check", {})
    
    # Inventory Check
    try:
        gt_inv = float(spot.get("gt_inventory", 0))
        view_inv = float(spot.get("view_inventory", 0))
        if abs(gt_inv - view_inv) < 0.1:
            score += 5
            feedback.append(f"Inventory aggregation correct ({gt_inv}).")
        else:
            feedback.append(f"Inventory incorrect. Expected {gt_inv}, got {view_inv}.")
    except:
        feedback.append("Could not verify inventory values.")

    # Sales Check
    try:
        gt_sales = float(spot.get("gt_sales", 0))
        view_sales = float(spot.get("view_sales", 0))
        if abs(gt_sales - view_sales) < 0.1:
            score += 5
            feedback.append(f"Sales aggregation correct ({gt_sales}).")
        else:
            feedback.append(f"Sales aggregation incorrect. Expected {gt_sales}, got {view_sales}.")
    except:
        feedback.append("Could not verify sales values.")

    # Burn Rate Check
    try:
        gt_burn = float(spot.get("gt_burn_rate", 0))
        view_burn = float(spot.get("view_burn_rate", 0))
        if abs(gt_burn - view_burn) < 0.01:
            score += 5
            feedback.append("Burn rate calculation correct.")
        else:
            feedback.append(f"Burn rate incorrect. Expected {gt_burn:.4f}, got {view_burn:.4f}.")
    except:
        feedback.append("Could not verify burn rate.")

    # Date Check
    gt_date = spot.get("gt_date", "").strip()
    view_date = spot.get("view_date", "").strip()
    if gt_date and view_date and gt_date == view_date:
        score += 10
        feedback.append(f"Projected stockout date correct ({gt_date}).")
    elif gt_date:
        feedback.append(f"Stockout date incorrect. Expected {gt_date}, got {view_date}.")
    
    # 4. Stored Procedure (20 pts)
    if result.get("proc_exists"):
        score += 10
        feedback.append("Stored procedure created.")
        if result.get("proc_works"):
            score += 10
            feedback.append("Stored procedure executes successfully.")
        else:
            feedback.append("Stored procedure execution failed or returned no rows.")
    else:
        feedback.append("Stored procedure Production.usp_GetCriticalStockouts NOT found.")

    # 5. CSV Export (25 pts)
    if result.get("csv_exists"):
        score += 10
        feedback.append("CSV file found.")
        
        row_count = int(result.get("csv_rows", 0))
        if row_count > 1: # Header + data
            score += 10
            feedback.append(f"CSV contains data ({row_count} lines).")
        
        if result.get("csv_header_match"):
            score += 5
            feedback.append("CSV header looks correct.")
    else:
        feedback.append("CSV export file NOT found.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }