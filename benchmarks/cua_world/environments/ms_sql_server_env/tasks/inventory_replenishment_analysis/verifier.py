#!/usr/bin/env python3
"""
Verifier for inventory_replenishment_analysis task.

Criteria:
1. Function 'fn_ProductDemandStats' exists and works.
2. View 'vw_InventoryHealthDashboard' exists with correct schema.
3. View logic produces correct Risk Levels (CRITICAL/WARNING/HEALTHY).
4. Table 'ReplenishmentQueue' exists and is populated correctly (filtered).
5. Anti-gaming: Objects created during task session.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inventory_replenishment_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Metadata
    metadata = task_info.get('metadata', {})
    required_cols = set(metadata.get('view_columns', []))
    
    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback = []
    
    # 1. Function Existence (10 pts)
    if result.get('fn_exists', 0) > 0:
        score += 10
        feedback.append("Function 'fn_ProductDemandStats' exists.")
    else:
        feedback.append("Function 'fn_ProductDemandStats' missing.")
        
    # 2. View Existence (15 pts)
    if result.get('vw_exists', 0) > 0:
        score += 15
        feedback.append("View 'vw_InventoryHealthDashboard' exists.")
    else:
        feedback.append("View 'vw_InventoryHealthDashboard' missing.")
        
    # 3. Table Existence (10 pts)
    if result.get('tbl_exists', 0) > 0:
        score += 10
        feedback.append("Table 'Production.ReplenishmentQueue' exists.")
    else:
        feedback.append("Table 'Production.ReplenishmentQueue' missing.")
        
    # 4. View Schema Check (15 pts)
    view_cols_str = result.get('view_columns', '')
    view_cols = [c.strip() for c in view_cols_str.split(',') if c.strip()]
    
    # We check if required columns are present (case insensitive matching usually handled by SQL, 
    # here we do simple set check)
    view_cols_set = {c.lower() for c in view_cols}
    required_cols_lower = {c.lower() for c in required_cols}
    
    missing_cols = required_cols_lower - view_cols_set
    if not missing_cols and len(required_cols) > 0:
        score += 15
        feedback.append("View has all required columns.")
    elif len(view_cols) >= 5:
        score += 5
        feedback.append(f"View has some columns, but missing: {missing_cols}")
    else:
        feedback.append("View columns check failed.")
        
    # 5. View Data & Logic (10 pts)
    if result.get('view_row_count', 0) >= 100:
        score += 5
        feedback.append(f"View returns data ({result.get('view_row_count')} rows).")
    else:
        feedback.append("View returns insufficient data (<100 rows).")

    invalid_risks = result.get('invalid_risk_count', 0)
    risk_levels = result.get('risk_levels', '')
    if invalid_risks == 0 and "CRITICAL" in risk_levels:
        score += 5
        feedback.append("Risk levels valid.")
    else:
        feedback.append(f"Risk levels invalid or missing CRITICAL data: {risk_levels}")

    # 6. Table Logic (20 pts)
    # Must have rows, no 'HEALTHY' rows, no negative qty
    rq_rows = result.get('rq_row_count', 0)
    rq_healthy = result.get('rq_healthy_count', 0)
    rq_neg = result.get('rq_negative_qty', 0)
    
    if rq_rows >= 5:
        score += 10
        feedback.append(f"ReplenishmentQueue populated ({rq_rows} rows).")
        
        if rq_healthy == 0:
            score += 5
            feedback.append("ReplenishmentQueue correctly excludes HEALTHY items.")
        else:
            feedback.append(f"ReplenishmentQueue contains {rq_healthy} HEALTHY items (should be 0).")
            
        if rq_neg == 0:
            score += 5
            feedback.append("SuggestedOrderQty values are valid (>= 0).")
        else:
            feedback.append(f"ReplenishmentQueue contains {rq_neg} negative quantities.")
    else:
        feedback.append("ReplenishmentQueue is empty or has too few rows.")

    # 7. Function Functionality (10 pts)
    if result.get('fn_test_rows', 0) > 0:
        score += 10
        feedback.append("Function returns data when queried directly.")
    else:
        feedback.append("Function returns no data or fails.")

    # 8. Anti-gaming (10 pts)
    if result.get('objects_created_during_task', False):
        score += 10
        feedback.append("Objects created during task session.")
    else:
        feedback.append("Objects appear pre-existing (timestamps predate task start).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }