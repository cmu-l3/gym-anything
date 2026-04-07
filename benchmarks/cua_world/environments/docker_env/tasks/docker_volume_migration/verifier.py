#!/usr/bin/env python3
"""
Verifier for Docker Volume Migration Task.

Criteria:
1. Container 'employee-db' must be running (20 pts)
2. Container must use a Docker Volume (not bind mount) (30 pts)
3. Volume name must be 'employee_db_data' (10 pts)
4. Data Integrity: 'employees' table exists and has 100 rows (40 pts)
   - Partial credit: Table exists but wrong count (10 pts)
   
Pass Threshold: 80 pts
"""

import json
import os
import sys

def verify_volume_migration(traj, env_info, task_info):
    # 1. Load Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    import tempfile
    temp_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/migration_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

    # 2. Extract Metrics
    is_running = result.get('is_running', 0)
    mount_type = result.get('mount_type', 'none')
    volume_name = result.get('volume_name', '')
    row_count = result.get('row_count', 0)
    table_exists = result.get('table_exists', 0)
    compose_updated = result.get('compose_uses_volume', 0)

    score = 0
    feedback = []

    # 3. Score - Running Status (20 pts)
    if is_running:
        score += 20
        feedback.append("Container is running (+20)")
    else:
        feedback.append("Container is NOT running (0/20)")

    # 4. Score - Storage Configuration (40 pts total)
    if mount_type == 'volume':
        score += 30
        feedback.append("Correctly using a Docker Volume (+30)")
        
        # Check volume name match
        if volume_name == 'employee_db_data':
            score += 10
            feedback.append("Volume name matches 'employee_db_data' (+10)")
        else:
            feedback.append(f"Volume name mismatch. Expected 'employee_db_data', got '{volume_name}' (0/10)")
    else:
        feedback.append(f"Incorrect mount type: {mount_type}. Expected 'volume'. (0/40)")

    # 5. Score - Data Integrity (40 pts total)
    if table_exists:
        if row_count == 100:
            score += 40
            feedback.append("Data integrity verified: 100 rows found (+40)")
        else:
            score += 10
            feedback.append(f"Data loss detected: Found {row_count} rows, expected 100 (10/40)")
    else:
        feedback.append("Database table 'employees' not found (0/40)")
        
    # Bonus/Sanity check on Compose file (not scored directly but good for feedback)
    if not compose_updated and mount_type == 'volume':
        feedback.append("Warning: Container uses volume but docker-compose.yml might not be updated.")

    # 6. Final Determination
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }