#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compose_credential_rotation(traj, env_info, task_info):
    """
    Verifies that the PostgreSQL password was rotated in a Docker Compose stack
    while preserving data.
    """
    
    # 1. Setup & Read Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    can_login_new = result.get('can_login_new_pass', False)
    can_login_old = result.get('can_login_old_pass', False)
    data_count = int(result.get('data_rows_count', 0))
    compose_updated_db = result.get('compose_updated_db', False)
    compose_updated_adminer = result.get('compose_updated_adminer', False)
    services_running = result.get('services_running', False)
    adminer_accessible = result.get('adminer_accessible', False)
    file_modified = result.get('file_modified_after_start', False)

    metadata = task_info.get('metadata', {})
    expected_rows = metadata.get('expected_rows', 5)

    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: Database accepts new password (25 pts)
    # This proves they actually ran ALTER USER or equivalent
    if can_login_new:
        score += 25
        feedback.append("Success: Database accepts new password (+25)")
    else:
        feedback.append("Fail: Database rejected new password (+0)")

    # Criterion 2: Database rejects old password (10 pts)
    # This proves the rotation actually happened
    if not can_login_old:
        score += 10
        feedback.append("Success: Database correctly rejects old password (+10)")
    else:
        feedback.append("Fail: Old password still works! (+0)")

    # Criterion 3: Data Integrity (20 pts)
    # This proves they didn't just delete the volume
    if data_count == expected_rows:
        score += 20
        feedback.append(f"Success: All {expected_rows} data rows preserved (+20)")
    elif data_count > 0:
        score += 10
        feedback.append(f"Partial: Data exists but count mismatch ({data_count}/{expected_rows}) (+10)")
    else:
        feedback.append("Fail: Database is empty! Volume data was lost (+0)")

    # Criterion 4: Compose File Updated (15 pts total)
    if compose_updated_db:
        score += 10
        feedback.append("Success: docker-compose.yml DB password updated (+10)")
    else:
        feedback.append("Fail: docker-compose.yml DB password NOT updated (+0)")
        
    if compose_updated_adminer:
        score += 5
        feedback.append("Success: docker-compose.yml Adminer password updated (+5)")
    else:
        feedback.append("Fail: docker-compose.yml Adminer password NOT updated (+0)")

    # Criterion 5: System Operational (20 pts total)
    if services_running:
        score += 15
        feedback.append("Success: Containers are running (+15)")
    else:
        feedback.append("Fail: Containers are not running (+0)")

    if adminer_accessible:
        score += 5
        feedback.append("Success: Adminer UI accessible (+5)")
    else:
        feedback.append("Fail: Adminer UI unreachable (+0)")

    # Criterion 6: Anti-Gaming (5 pts)
    if file_modified:
        score += 5
    else:
        feedback.append("Warning: docker-compose.yml not modified after task start (+0)")

    # 4. Final Verdict
    # Mandatory criteria: Must be able to login with new pass AND have data
    mandatory_met = can_login_new and (data_count >= expected_rows)
    
    passed = (score >= 70) and mandatory_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }