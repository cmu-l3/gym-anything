#!/usr/bin/env python3
"""
Verifier for chinook_analytics_schema task.
Checks if the agent correctly created the DB connection, View, Table, Indexes, and Script.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_analytics_schema(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Connection (10 pts)
    conn = result.get('connection', {})
    if conn.get('found'):
        score += 5
        feedback.append("DBeaver connection created.")
        if conn.get('correct_path'):
            score += 5
        else:
            feedback.append("Warning: Connection path might be incorrect.")
    else:
        feedback.append("DBeaver connection 'ChinookAnalytics' not found.")

    # 2. View (25 pts)
    view = result.get('view', {})
    gt = result.get('ground_truth', {})
    
    if view.get('exists'):
        score += 10
        feedback.append("View 'vw_monthly_revenue' exists.")
        
        # Check rows
        gt_rows = gt.get('month_count', 0)
        # Allow slight variance if logic differs slightly (e.g., date parsing)
        if abs(view.get('row_count', 0) - gt_rows) <= 2 and gt_rows > 0:
            score += 5
        else:
            feedback.append(f"View row count mismatch: got {view.get('row_count')}, expected {gt_rows}.")

        # Check Spot Revenue (Accuracy)
        try:
            val_view = float(view.get('spot_revenue', 0))
            val_gt = float(gt.get('spot_check_revenue', 0))
            # Tolerance 1.0
            if abs(val_view - val_gt) < 1.0:
                score += 10
            else:
                feedback.append(f"View revenue calc incorrect: got {val_view}, expected {val_gt}.")
        except:
            feedback.append("Could not parse view revenue value.")
    else:
        feedback.append("View 'vw_monthly_revenue' not found.")

    # 3. Table & Data (40 pts)
    table = result.get('table', {})
    if table.get('exists'):
        score += 10
        feedback.append("Table 'customer_lifetime_value' exists.")
        
        # Rows
        gt_cust = gt.get('customer_count', 59)
        if table.get('row_count') == gt_cust:
            score += 5
        else:
            feedback.append(f"Table row count {table.get('row_count')} != {gt_cust}.")
            
        # Segments Logic Check
        s_high = table.get('segment_high', 0)
        s_med = table.get('segment_med', 0)
        s_low = table.get('segment_low', 0)
        
        gt_high = gt.get('high_segment_count', 0)
        gt_med = gt.get('medium_segment_count', 0)
        gt_low = gt.get('low_segment_count', 0)
        
        # 25 pts for data correctness distributed
        seg_score = 0
        if s_high == gt_high: seg_score += 8
        if s_med == gt_med: seg_score += 8
        if s_low == gt_low: seg_score += 9
        
        score += seg_score
        if seg_score < 25:
            feedback.append(f"Segment logic mismatch. Found H:{s_high}/M:{s_med}/L:{s_low}. Expected H:{gt_high}/M:{gt_med}/L:{gt_low}.")
    else:
        feedback.append("Table 'customer_lifetime_value' not found.")

    # 4. Indexes (10 pts)
    idxs = result.get('indexes', {})
    if idxs.get('segment'): score += 5
    else: feedback.append("Index 'idx_clv_segment' missing.")
    
    if idxs.get('country'): score += 5
    else: feedback.append("Index 'idx_clv_country' missing.")

    # 5. Script (15 pts)
    script = result.get('script', {})
    if script.get('exists'):
        score += 5
        feedback.append("SQL script file saved.")
        if script.get('valid_content'):
            score += 10
        else:
            feedback.append("SQL script content missing keywords (CREATE VIEW/TABLE/INSERT).")
    else:
        feedback.append("SQL script file not found.")

    # Anti-gaming check
    if not result.get('anti_gaming', {}).get('db_modified', False):
        score = 0
        feedback = ["ANTI-GAMING: Database file was not modified during the task."]

    passed = score >= 60 and table.get('exists') and view.get('exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }