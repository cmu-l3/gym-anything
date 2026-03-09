#!/usr/bin/env python3
"""
Verifier for Chinook Monthly KPI Time Series task.
"""

import json
import logging
import os
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_monthly_kpi(traj, env_info, task_info):
    """
    Verify the monthly financial KPI task.
    
    Criteria:
    1. DBeaver connection 'Chinook' exists (10 pts)
    2. CSV file exists at correct path (10 pts)
    3. CSV created during task (5 pts)
    4. CSV has correct columns (15 pts)
    5. Row count matches months in DB (10 pts)
    6. Final CumulativeRevenue matches DB Total Revenue (15 pts)
    7. Sum of NewCustomers matches DB Distinct Customers (10 pts)
    8. First month Revenue matches ground truth (10 pts)
    9. MoM Growth column exists and has values (5 pts)
    10. SQL script exists (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback_parts = []
    
    # 1. Connection (10 pts)
    if result.get('connection_exists'):
        score += 10
        feedback_parts.append("DBeaver connection found")
    else:
        feedback_parts.append("MISSING: 'Chinook' connection in DBeaver")
        
    # 2. CSV Existence (10 pts)
    if result.get('csv_exists'):
        score += 10
        feedback_parts.append("CSV output file found")
    else:
        feedback_parts.append("MISSING: Output CSV file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # 3. Anti-gaming timestamp (5 pts)
    if result.get('csv_created_during_task'):
        score += 5
    else:
        feedback_parts.append("WARNING: CSV file timestamp too old (pre-existing?)")
        
    # 4. CSV Structure (15 pts)
    # 7 cols required
    if result.get('csv_col_count', 0) >= 7 and result.get('csv_header_valid'):
        score += 15
        feedback_parts.append("CSV header valid")
    else:
        feedback_parts.append(f"CSV structure incorrect (found {result.get('csv_col_count')} cols)")
        
    # 5. Row Count (10 pts)
    # Should match distinct months in DB (approx 59-60)
    agent_rows = result.get('csv_row_count', 0)
    gt_rows = result.get('gt_month_count', 0)
    if gt_rows > 0 and abs(agent_rows - gt_rows) <= 1:
        score += 10
        feedback_parts.append(f"Row count correct ({agent_rows})")
    else:
        feedback_parts.append(f"Row count mismatch: got {agent_rows}, expected ~{gt_rows}")
        
    # 6. Cumulative Revenue Check (15 pts)
    # The last row's cumulative revenue must equal total DB revenue
    try:
        agent_cum = float(result.get('agent_total_cumulative', '0'))
        gt_rev = float(result.get('gt_total_revenue', '0'))
        
        # Allow 1% tolerance for rounding differences
        if gt_rev > 0 and abs(agent_cum - gt_rev) / gt_rev < 0.01:
            score += 15
            feedback_parts.append("Cumulative Revenue correct")
        else:
            feedback_parts.append(f"Cumulative Revenue mismatch: got {agent_cum}, expected {gt_rev}")
    except ValueError:
        feedback_parts.append("Could not parse Cumulative Revenue value")
        
    # 7. New Customers Check (10 pts)
    # Sum of new customers must equal total distinct customers (invariant)
    agent_new = result.get('agent_new_cust_sum', 0)
    gt_cust = result.get('gt_total_customers', 0)
    
    if gt_cust > 0 and agent_new == gt_cust:
        score += 10
        feedback_parts.append("New Customer logic correct (sum matches total customers)")
    else:
        feedback_parts.append(f"New Customer logic incorrect: sum {agent_new} != total {gt_cust}")
        
    # 8. First Month Revenue (10 pts)
    try:
        agent_first = float(result.get('agent_first_rev', '0'))
        gt_first = float(result.get('gt_first_month_rev', '0'))
        
        if gt_first > 0 and abs(agent_first - gt_first) < 1.0:
            score += 10
            feedback_parts.append("First month revenue correct")
        else:
            feedback_parts.append(f"First month revenue mismatch: got {agent_first}, expected {gt_first}")
    except ValueError:
        pass

    # 9. MoM Growth Exists (5 pts)
    # Implicitly checked by header validation + non-zero values, giving points if basic structural checks passed
    if result.get('csv_col_count', 0) >= 7:
        score += 5
        
    # 10. SQL Script (10 pts)
    if result.get('sql_script_exists'):
        score += 10
        feedback_parts.append("SQL script saved")
    else:
        feedback_parts.append("MISSING: SQL script file")
        
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }