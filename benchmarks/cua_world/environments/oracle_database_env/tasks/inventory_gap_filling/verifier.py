#!/usr/bin/env python3
"""
Verifier for Inventory Gap Filling task.

Criteria:
1. View DAILY_INVENTORY_FULL exists (10 pts)
2. Total rows = 93 (3 products * 31 days) (20 pts)
3. Date coverage complete (Jan 1-31) (20 pts)
4. Gap filling logic correct (Scenario A) (30 pts)
5. Multiple updates handled (Scenario C) (10 pts)
6. Initial zeros handling (Scenario B) (10 pts)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inventory_gap_filling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/inventory_gap_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. View Exists
    if result.get("view_exists"):
        score += 10
        feedback.append("View created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": f"View DAILY_INVENTORY_FULL not found. Error: {result.get('error')}"}

    # 2. Row Count & Date Coverage
    # Expected: 3 products * 31 days = 93 rows
    total_rows = result.get("total_rows", 0)
    distinct_dates = result.get("distinct_dates", 0)
    distinct_products = result.get("distinct_products", 0)

    if total_rows == 93:
        score += 20
        feedback.append("Row count correct (93).")
    else:
        feedback.append(f"Row count incorrect: {total_rows} (Expected 93).")

    if distinct_dates == 31:
        score += 20
        feedback.append("Date generation correct (31 days).")
    else:
        feedback.append(f"Missing dates: found {distinct_dates}/31.")

    # 3. Logic Checks
    
    # Scenario A: Gap Fill (Jan 5 for Prod 500 should be 10)
    val_a = result.get("scenario_a_gap_fill")
    if val_a == 10:
        score += 30
        feedback.append("Gap filling logic correct (LOCF confirmed).")
    else:
        feedback.append(f"Gap filling logic failed. Jan 5 (Prod 500) was {val_a}, expected 10.")

    # Scenario C: Multi Update (Jan 1 for Prod 502 should be 110)
    val_c = result.get("scenario_c_multi_update")
    if val_c == 110:
        score += 10
        feedback.append("Multiple daily updates handled correct (max LOG_ID taken).")
    else:
        feedback.append(f"Multi-update logic failed. Jan 1 (Prod 502) was {val_c}, expected 110.")

    # Scenario B: Initial Zeros (Jan 1 for Prod 501 should be 0)
    val_b = result.get("scenario_b_initial")
    if val_b == 0:
        score += 10
        feedback.append("Pre-history dates default to 0.")
    elif val_b is None:
        feedback.append("Pre-history dates are NULL (expected 0).")
    else:
        feedback.append(f"Pre-history dates incorrect. Was {val_b}, expected 0.")

    passed = (score >= 60) and result.get("view_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }