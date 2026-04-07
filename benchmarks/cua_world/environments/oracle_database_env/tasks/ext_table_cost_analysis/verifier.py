#!/usr/bin/env python3
"""
Verifier for External Table Cost Analysis task.
Checks if Oracle external tables and views were created correctly and data was exported.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ext_table_cost_analysis(traj, env_info, task_info):
    """
    Verify the creation of external tables, analytical view, and exported report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    
    db_objs = result.get('database_objects', {})
    out_file = result.get('output_file', {})
    metadata = task_info.get('metadata', {})

    # --- 1. External Table: EXT_COUNTRY_COSTS (25 pts) ---
    t1 = db_objs.get('ext_country_costs', {})
    if t1.get('exists'):
        score += 10
        if t1.get('is_external'):
            score += 8
            feedback.append("EXT_COUNTRY_COSTS created as external table.")
        else:
            feedback.append("EXT_COUNTRY_COSTS exists but is NOT external (regular table used?).")
        
        # Check rows (expect ~25)
        count = int(t1.get('row_count', 0))
        if count >= 20:
            score += 7
            feedback.append(f"EXT_COUNTRY_COSTS returns data ({count} rows).")
        else:
            feedback.append(f"EXT_COUNTRY_COSTS has insufficient data ({count} rows).")
    else:
        feedback.append("EXT_COUNTRY_COSTS table missing.")

    # --- 2. External Table: EXT_MARKET_SALARIES (25 pts) ---
    t2 = db_objs.get('ext_market_salaries', {})
    if t2.get('exists'):
        score += 10
        if t2.get('is_external'):
            score += 8
            feedback.append("EXT_MARKET_SALARIES created as external table.")
        else:
            feedback.append("EXT_MARKET_SALARIES exists but is NOT external.")
        
        # Check rows (expect ~19)
        count = int(t2.get('row_count', 0))
        if count >= 15:
            score += 7
            feedback.append(f"EXT_MARKET_SALARIES returns data ({count} rows).")
        else:
            feedback.append(f"EXT_MARKET_SALARIES has insufficient data ({count} rows).")
    else:
        feedback.append("EXT_MARKET_SALARIES table missing.")

    # --- 3. View: EMPLOYEE_COST_ANALYSIS (35 pts) ---
    view = db_objs.get('employee_cost_analysis_view', {})
    if view.get('exists'):
        score += 10
        feedback.append("EMPLOYEE_COST_ANALYSIS view exists.")
        
        # Check if it returns data (joined correctly)
        # HR schema usually has ~107 employees. Inner joining might reduce this if keys mismatch,
        # but setup data uses standard codes. Expect > 80.
        v_count = int(view.get('row_count', 0))
        if v_count >= 80:
            score += 8
            feedback.append(f"View returns joined data ({v_count} rows).")
        else:
            feedback.append(f"View returns few rows ({v_count}). Joins might be incorrect.")

        # Check dependencies (must use the external tables)
        deps = int(view.get('dependency_count', 0))
        if deps >= 2:
            score += 7
            feedback.append("View correctly references external tables.")
        else:
            feedback.append("View does NOT reference both external tables.")

        # Check columns (Calculated fields)
        cols = view.get('columns', '')
        if 'SALARY_VS_MARKET_PCT' in cols:
            score += 5
        else:
            feedback.append("Missing calculated column: SALARY_VS_MARKET_PCT.")
            
        if 'COST_ADJUSTED_SALARY' in cols:
            score += 5
        else:
            feedback.append("Missing calculated column: COST_ADJUSTED_SALARY.")
    else:
        feedback.append("EMPLOYEE_COST_ANALYSIS view missing.")

    # --- 4. Exported File (15 pts) ---
    if out_file.get('exists'):
        score += 8
        feedback.append("Output file found.")
        
        if out_file.get('line_count', 0) >= 80:
            score += 5
            feedback.append("Output file has sufficient content.")
        
        if out_file.get('has_salary_data'):
            score += 2
            feedback.append("Output file contains salary figures.")
    else:
        feedback.append("Output report file missing.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }