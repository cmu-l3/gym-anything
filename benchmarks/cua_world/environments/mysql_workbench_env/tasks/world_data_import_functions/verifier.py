#!/usr/bin/env python3
"""
Verifier for world_data_import_functions task.

Verifies:
1. Database and Table structure (Schema, Rows)
2. Foreign Key Constraint correctness
3. Stored Function logic (via test execution output)
4. View creation and content
5. Export file existence and freshness
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_world_data_import(traj, env_info, task_info):
    """
    Verify the complete import-analyze-export workflow.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 1. Database & Table Creation (20 pts)
    # 5 pts for DB, 15 pts for Table with data
    if result.get('db_exists', 0) == 1:
        score += 5
        feedback_parts.append("Database 'world_analytics' created")
        
        if result.get('table_exists', 0) == 1:
            row_count = result.get('row_count', 0)
            if row_count >= 200:
                score += 15
                feedback_parts.append(f"Table 'country_indicators' populated ({row_count} rows)")
            elif row_count > 0:
                score += 5
                feedback_parts.append(f"Table 'country_indicators' has incomplete data ({row_count} rows)")
            else:
                feedback_parts.append("Table 'country_indicators' is empty")
                
            if result.get('columns_match', 0) == 1:
                score += 10
                feedback_parts.append("Table schema matches requirements")
            else:
                feedback_parts.append("Table schema has missing columns")
        else:
            feedback_parts.append("Table 'country_indicators' missing")
    else:
        feedback_parts.append("Database 'world_analytics' missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Foreign Key (10 pts)
    if result.get('fk_exists', 0) > 0:
        score += 10
        feedback_parts.append("Foreign Key constraint verified")
    else:
        feedback_parts.append("Foreign Key constraint missing or incorrect")

    # 3. Functions (30 pts)
    # Dev Level Function
    if result.get('fn_dev_exists', 0) == 1:
        score += 5
        test_res = result.get('fn_dev_test_result', '')
        # Expected: High,Medium,Low
        if 'High' in test_res and 'Medium' in test_res and 'Low' in test_res:
            score += 10
            feedback_parts.append("fn_development_level logic correct")
        else:
            feedback_parts.append(f"fn_development_level returned unexpected values: {test_res}")
    else:
        feedback_parts.append("fn_development_level missing")

    # Density Function
    if result.get('fn_dens_exists', 0) == 1:
        score += 5
        test_res = result.get('fn_dens_test_result', '')
        # Expected: Dense,Moderate,Sparse
        if 'Dense' in test_res and 'Moderate' in test_res and 'Sparse' in test_res:
            score += 10
            feedback_parts.append("fn_density_category logic correct")
        else:
            feedback_parts.append(f"fn_density_category returned unexpected values: {test_res}")
    else:
        feedback_parts.append("fn_density_category missing")

    # 4. View (15 pts)
    if result.get('view_exists', 0) == 1:
        view_rows = result.get('view_rows', 0)
        if view_rows >= 200:
            score += 15
            feedback_parts.append("View 'v_country_analysis' created and functional")
        else:
            score += 5
            feedback_parts.append("View created but returned few/no rows")
    else:
        feedback_parts.append("View 'v_country_analysis' missing")

    # 5. Export (15 pts)
    if result.get('file_exists', False):
        if result.get('file_created_during_task', False):
            file_rows = result.get('file_rows', 0)
            if file_rows >= 200:
                score += 15
                feedback_parts.append("Export file created successfully")
            else:
                score += 5
                feedback_parts.append(f"Export file incomplete ({file_rows} rows)")
        else:
            feedback_parts.append("Export file timestamp invalid (old file?)")
    else:
        feedback_parts.append("Export file not found")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }