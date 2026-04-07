#!/usr/bin/env python3
"""
Verifier for create_patient_view task.

Verifies:
1. SQL View 'vue_patients_complete' exists in DrTuxTest database.
2. View contains all 11 required columns with correct aliases.
3. View logic correctly calculates age.
4. View logic correctly filters for 'Dossier' type.
5. View logic uses LEFT JOIN.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_patient_view(traj, env_info, task_info):
    """
    Verify the patient SQL view creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_columns = set(metadata.get('required_columns', []))
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. View Exists (20 pts)
    if result.get('view_exists', False):
        score += 20
        feedback_parts.append("View 'vue_patients_complete' created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "View 'vue_patients_complete' was not found in the database."}

    # 2. Check Columns (20 pts)
    # 2 pts per column, max 20. If all 11 present, full points.
    actual_columns = set(result.get('columns', []))
    missing_columns = required_columns - actual_columns
    
    if not missing_columns:
        score += 20
        feedback_parts.append("All required columns are present.")
    else:
        # Deduct 2 points for each missing column
        penalty = len(missing_columns) * 2
        col_score = max(0, 20 - penalty)
        score += col_score
        feedback_parts.append(f"Missing columns: {', '.join(missing_columns)}.")

    # 3. Check Logic: Age Calculation (15 pts)
    logic_checks = result.get('logic_verification', {})
    if logic_checks.get('age_calculation_correct', False):
        score += 15
        feedback_parts.append("Age calculation logic is correct.")
    else:
        feedback_parts.append("Age calculation verification failed (values didn't match expectation).")

    # 4. Check Logic: Filter (10 pts)
    if logic_checks.get('filter_dossier_correct', False):
        score += 10
        feedback_parts.append("Filter for 'Dossier' type is correct.")
    else:
        feedback_parts.append("Filter verification failed (non-Dossier records found in view).")

    # 5. Check Definition keywords (15 pts)
    create_stmt = result.get('create_statement', "").upper()
    
    # Check for JOIN
    if "JOIN" in create_stmt:
        if "LEFT JOIN" in create_stmt:
            score += 10
            feedback_parts.append("Used LEFT JOIN correctly.")
        else:
            score += 5
            feedback_parts.append("Used JOIN, but not LEFT JOIN (potential data loss for patients without demographics).")
    else:
        feedback_parts.append("No JOIN detected in view definition.")

    # Check for timestampdiff
    if "TIMESTAMPDIFF" in create_stmt and "YEAR" in create_stmt:
        score += 5
        feedback_parts.append("Used TIMESTAMPDIFF for age calculation.")
    elif "AGE_ANNEES" in actual_columns:
        # If column exists but method different, give partial
        score += 2
        feedback_parts.append("Age column exists but method differs from recommended TIMESTAMPDIFF.")

    # 6. Data Retrieval (20 pts)
    row_count = result.get('row_count', 0)
    if row_count > 0:
        score += 20
        feedback_parts.append(f"View returns data ({row_count} rows).")
    else:
        feedback_parts.append("View returns 0 rows (Verify data/logic).")

    passed = score >= 60 and result.get('view_exists', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }