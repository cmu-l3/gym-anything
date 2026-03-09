#!/usr/bin/env python3
"""
Verifier for Chinook Territory Realignment Task

Criteria:
1. DBeaver connection 'Chinook' exists.
2. Table 'territory_map' exists in DB and has data (import success).
3. Customers table updated correctly (Logic verification).
4. Verification report CSV exists and is valid.
5. SQL script exists.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_territory_realignment(traj, env_info, task_info):
    """
    Verify the territory realignment task.
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
    if result.get('connection_exists', False):
        score += 10
        feedback_parts.append("Connection 'Chinook' created.")
    else:
        feedback_parts.append("Connection 'Chinook' NOT found.")

    # 2. Import Validation (30 pts)
    map_exists = result.get('table_map_exists', False)
    row_count = result.get('map_row_count', 0)
    
    if map_exists:
        score += 20
        feedback_parts.append("Table 'territory_map' exists.")
        # Expecting around 24 rows from the setup script
        if 20 <= row_count <= 30:
            score += 10
            feedback_parts.append(f"Import row count correct ({row_count}).")
        else:
            feedback_parts.append(f"Import row count suspicious ({row_count}, expected ~24).")
    else:
        feedback_parts.append("Table 'territory_map' NOT found.")

    # 3. Update Logic Validation (30 pts)
    # Checking specific known updates (USA and Canada should move to Rep 4)
    usa_ok = result.get('usa_updated_correctly', False)
    canada_ok = result.get('canada_updated_correctly', False)
    
    if usa_ok and canada_ok:
        score += 30
        feedback_parts.append("Customer records updated correctly (USA/Canada -> Rep 4).")
    elif usa_ok or canada_ok:
        score += 15
        feedback_parts.append("Customer records partially updated.")
    else:
        feedback_parts.append("Customer records NOT updated correctly (Rep IDs did not change as expected).")

    # 4. Report Validation (15 pts)
    if result.get('report_exists', False):
        if result.get('report_valid', False):
            score += 15
            feedback_parts.append("Verification report CSV created and valid.")
        else:
            score += 5
            feedback_parts.append("Verification report CSV exists but header content mismatch.")
    else:
        feedback_parts.append("Verification report CSV NOT found.")

    # 5. Script Validation (15 pts)
    if result.get('script_exists', False):
        score += 15
        feedback_parts.append("SQL script saved.")
    else:
        feedback_parts.append("SQL script NOT found.")

    # Anti-gaming check (files created during task)
    if result.get('report_exists', False) and not result.get('report_created_during_task', False):
        score = max(0, score - 20)
        feedback_parts.append("WARNING: Report file timestamp predates task start.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }