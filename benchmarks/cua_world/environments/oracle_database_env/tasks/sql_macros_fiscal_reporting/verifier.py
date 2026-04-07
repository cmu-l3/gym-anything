#!/usr/bin/env python3
"""
Verifier for SQL Macros Fiscal Reporting task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sql_macros(traj, env_info, task_info):
    """
    Verifies that:
    1. SCALAR SQL Macro GET_FISCAL_YEAR exists and handles Oct 1 cutoff correctly.
    2. TABLE SQL Macro GET_HIGH_IMPACT_SALES exists and filters Region/Amount/Weekend.
    3. CSV report exists and matches ground truth data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get("db_error"):
        return {"passed": False, "score": 0, "feedback": f"Database check failed: {result['db_error']}"}

    score = 0
    feedback_parts = []

    # Criterion 1: Scalar Macro (20 pts exists + 20 pts logic)
    if result.get("scalar_macro_exists"):
        if result.get("scalar_macro_is_macro"):
            score += 20
            feedback_parts.append("Scalar Macro created correctly (+20)")
        else:
            score += 10
            feedback_parts.append("Function created but not identified as SQL MACRO (+10)")
        
        logic_score = result.get("scalar_macro_logic_score", 0)
        if logic_score == 1.0:
            score += 20
            feedback_parts.append("Fiscal Year logic correct (+20)")
        elif logic_score > 0:
            score += 10
            feedback_parts.append("Fiscal Year logic partially correct (+10)")
        else:
            feedback_parts.append("Fiscal Year logic incorrect (0)")
    else:
        feedback_parts.append("GET_FISCAL_YEAR not found")

    # Criterion 2: Table Macro (20 pts exists + 20 pts logic)
    if result.get("table_macro_exists"):
        if result.get("table_macro_is_macro"):
            score += 20
            feedback_parts.append("Table Macro created correctly (+20)")
        else:
            score += 10
            feedback_parts.append("Function created but not identified as TABLE MACRO (+10)")
        
        if result.get("table_macro_logic_score", 0) == 1.0:
            score += 20
            feedback_parts.append("Filtering logic (Region/Amt/Weekend) correct (+20)")
        else:
            feedback_parts.append("Filtering logic incorrect or returns wrong rows (0)")
    else:
        feedback_parts.append("GET_HIGH_IMPACT_SALES not found")

    # Criterion 3: Report (10 pts exists + 10 pts accuracy)
    if result.get("report_exists"):
        score += 5
        if result.get("report_valid_format"):
            score += 5
            feedback_parts.append("Report file exists with valid headers (+10)")
            
            accuracy = result.get("report_data_accuracy", 0.0)
            if accuracy == 1.0:
                score += 10
                feedback_parts.append("Report data 100% accurate (+10)")
            elif accuracy > 0.5:
                score += 5
                feedback_parts.append("Report data partially accurate (+5)")
            else:
                feedback_parts.append("Report data does not match ground truth")
        else:
            feedback_parts.append("Report file exists but format/headers are wrong (+5)")
    else:
        feedback_parts.append("Report file not found")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }