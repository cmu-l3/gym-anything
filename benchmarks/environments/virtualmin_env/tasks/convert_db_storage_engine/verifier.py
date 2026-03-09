#!/usr/bin/env python3
"""
Verifier for convert_db_storage_engine task.

Scoring Criteria:
1. Storage Engine is InnoDB (60 pts)
2. Row Count is preserved (30 pts)
3. Data Integrity (checksum) matches (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_convert_db_storage_engine(traj, env_info, task_info):
    """
    Verify that the database table was converted to InnoDB and data was preserved.
    """
    # 1. Setup - retrieve result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract Metrics
    final_engine = result.get('final_engine', 'Unknown')
    engine_converted = result.get('engine_converted', False)
    data_preserved = result.get('data_preserved', False)
    integrity_passed = result.get('integrity_passed', False)
    initial_rows = result.get('initial_row_count', 0)
    final_rows = result.get('final_row_count', 0)

    score = 0
    feedback_parts = []

    # 3. Score Calculation

    # Criterion 1: Engine Conversion (60 pts)
    if engine_converted and final_engine.lower() == 'innodb':
        score += 60
        feedback_parts.append("Success: Table converted to InnoDB")
    else:
        feedback_parts.append(f"Fail: Table engine is {final_engine} (expected InnoDB)")

    # Criterion 2: Data Preservation (30 pts)
    # We require data to be present. If table is empty, this fails.
    if data_preserved:
        score += 30
        feedback_parts.append(f"Success: Row count preserved ({final_rows} rows)")
    else:
        if final_rows == 0:
            feedback_parts.append("Fail: Table is empty (data lost)")
        else:
            feedback_parts.append(f"Fail: Row count changed (Initial: {initial_rows}, Final: {final_rows})")

    # Criterion 3: Data Integrity (10 pts)
    # Checks if the content checksum matches
    if integrity_passed:
        score += 10
        feedback_parts.append("Success: Data integrity check passed")
    elif data_preserved:
        # If count matches but hash doesn't, data was altered
        feedback_parts.append("Warning: Data content altered (checksum mismatch)")

    # 4. Final Assessment
    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }