#!/usr/bin/env python3
"""
Verifier for multidimensional_sales_cube task.

Criteria:
1. Objects exist (Function, View, Proc, Table)
2. Table is populated with aggregated data (GROUPING SETS/ROLLUP used)
3. Grand Total matches reference value (within 1%)
4. View uses CROSS APPLY
5. Report file exists and contains valid data
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multidimensional_sales_cube(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/cube_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract values
    tvf_exists = result.get('tvf_exists', False)
    view_exists = result.get('view_exists', False)
    proc_exists = result.get('proc_exists', False)
    table_exists = result.get('table_exists', False)
    row_count = result.get('row_count', 0)
    distinct_levels = result.get('distinct_levels', 0)
    grand_total_row_exists = result.get('grand_total_row_exists', False)
    
    # Revenue comparison
    try:
        grand_total_rev = float(str(result.get('grand_total_revenue', '0')).replace(',', ''))
        ref_revenue = float(str(result.get('reference_revenue', '0')).replace(',', ''))
    except ValueError:
        grand_total_rev = 0.0
        ref_revenue = 0.0

    # 1. Object Existence (30 pts)
    if tvf_exists: score += 10
    if view_exists: score += 10
    if proc_exists: score += 10
    
    if not (tvf_exists and view_exists and proc_exists):
        feedback_parts.append("Missing required database objects.")

    # 2. Table Content & Aggregation (30 pts)
    if table_exists and row_count >= 50:
        score += 10
        feedback_parts.append(f"Table populated ({row_count} rows).")
    elif table_exists and row_count > 0:
        score += 5
        feedback_parts.append("Table has few rows (expected >= 50).")
    else:
        feedback_parts.append("Table empty or missing.")

    if distinct_levels >= 4:
        score += 10
        feedback_parts.append(f"Multiple aggregation levels found ({distinct_levels}).")
    elif distinct_levels > 1:
        score += 5
        feedback_parts.append("Some aggregation levels found.")
    
    if grand_total_row_exists:
        score += 10
        feedback_parts.append("Grand total row exists.")

    # 3. Accuracy (20 pts)
    revenue_ok = False
    if ref_revenue > 0 and grand_total_rev > 0:
        diff = abs(grand_total_rev - ref_revenue)
        pct_diff = (diff / ref_revenue) * 100
        if pct_diff <= 1.0:
            score += 20
            revenue_ok = True
            feedback_parts.append("Revenue calculation accurate.")
        else:
            feedback_parts.append(f"Revenue mismatch (Diff: {pct_diff:.2f}%).")
    else:
        feedback_parts.append("Could not verify revenue accuracy.")

    # 4. Technical Constraints (10 pts)
    if result.get('tvf_is_inline', False):
        score += 5
    if result.get('cross_apply_used', False):
        score += 5
        feedback_parts.append("CROSS APPLY usage verified.")

    # 5. Report File (10 pts)
    if result.get('report_exists', False) and result.get('report_created_during_task', False):
        if result.get('report_content_valid', False):
            score += 10
            feedback_parts.append("Report file valid.")
        else:
            score += 5
            feedback_parts.append("Report file exists but content questionable.")

    # Final Check
    passed = (score >= 70) and revenue_ok and table_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }