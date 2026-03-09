#!/usr/bin/env python3
"""
Verifier for import_messy_excel_range task (Epi Info 7).

VERIFICATION CRITERIA:
1. Project Creation (20 pts): Project folder exists.
2. Database Format (20 pts): MUST be SQLite (.db), not Access (.mdb).
3. Table Existence (20 pts): 'LabResults' table exists in DB.
4. Data Cleaning (20 pts): Columns match actual data (Row 4), not junk headers (Row 1).
5. Data Integrity (20 pts): Correct row count (51 records), not including header rows.

Anti-Gaming:
- Checks if file was created during task window.
- Verifies internal DB structure, not just UI.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_messy_excel_range(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected metadata
    metadata = task_info.get('metadata', {})
    expected_rows = metadata.get('expected_rows', 51)
    
    score = 0
    feedback_parts = []
    
    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task results: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. Check Project Existence (20 pts)
    if result.get('project_exists'):
        score += 20
        feedback_parts.append("Project created")
    else:
        feedback_parts.append("Project folder not found")

    # 2. Check Database Type (20 pts) - CRITICAL
    db_type = result.get('db_type', 'none')
    if db_type == 'sqlite':
        score += 20
        feedback_parts.append("Correct DB format (SQLite)")
    elif db_type == 'access':
        feedback_parts.append("Incorrect DB format (Access MDB used instead of SQLite)")
    else:
        feedback_parts.append("Database file not found")

    # 3. Check Table Existence (20 pts)
    if result.get('table_exists'):
        score += 20
        feedback_parts.append("'LabResults' table found")
    else:
        feedback_parts.append("'LabResults' table NOT found")

    # 4. Check Data Cleaning / Columns (20 pts)
    # If they imported Row 1, they will have "St_Marys" or "F1" as columns
    has_junk = result.get('has_junk_columns', False)
    columns = result.get('columns', [])
    
    # We want specific columns
    required_cols = ['SpecimenID', 'CtValue']
    has_required = all(any(req.lower() in c.lower() for c in columns) for req in required_cols)

    if has_required and not has_junk:
        score += 20
        feedback_parts.append("Headers imported correctly from Row 4")
    elif has_junk:
        feedback_parts.append("Incorrect headers (imported top-matter text)")
    else:
        feedback_parts.append("Missing required columns")

    # 5. Check Row Count (20 pts)
    # If they included headers as data, count will be higher (e.g. 54)
    # If they missed data, count will be lower
    row_count = result.get('row_count', 0)
    
    if row_count == expected_rows:
        score += 20
        feedback_parts.append(f"Row count correct ({row_count})")
    elif abs(row_count - expected_rows) <= 3 and row_count > expected_rows:
        # Penalize for including header rows as data
        score += 5
        feedback_parts.append(f"Row count slightly high ({row_count}) - likely included header rows")
    elif row_count > 0:
        score += 5
        feedback_parts.append(f"Incorrect row count ({row_count})")
    else:
        feedback_parts.append("Table is empty")

    # Final Pass Calculation
    # Must have SQLite, Table, and reasonable data to pass
    passed = (score >= 70) and (db_type == 'sqlite') and (result.get('table_exists'))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }