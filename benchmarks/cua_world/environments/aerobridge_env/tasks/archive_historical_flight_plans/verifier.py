#!/usr/bin/env python3
"""
Verifier for archive_historical_flight_plans task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_archive_historical_flight_plans(traj, env_info, task_info):
    """
    Verify that historical flight plans were archived to JSON and deleted from DB,
    while active flight plans were preserved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/final_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Archive File Existence and Validity (20 pts)
    if result.get("archive_exists"):
        if result.get("archive_valid_json"):
            score += 20
            feedback_parts.append("Archive file exists and is valid JSON (+20)")
        else:
            score += 10
            feedback_parts.append("Archive file exists but contains invalid JSON (+10)")
    else:
        feedback_parts.append("Archive file '/home/ga/archive_pre2024.json' not found")

    # 2. Archive Content (30 pts)
    # Did we find the specific historical names in the file?
    found_names = result.get("archived_names_found", [])
    # We expect 3 historical records
    if len(found_names) >= 3:
        score += 30
        feedback_parts.append(f"Archive contains all {len(found_names)} expected historical records (+30)")
    elif len(found_names) > 0:
        partial = len(found_names) * 10
        score += partial
        feedback_parts.append(f"Archive contains {len(found_names)}/3 expected historical records (+{partial})")
    else:
        feedback_parts.append("Archive does not contain the expected historical flight names")

    # 3. Database Purge Verification (25 pts)
    # Historical count in DB should be 0
    hist_count = result.get("db_historical_count", -1)
    if hist_count == 0:
        score += 25
        feedback_parts.append("Historical records successfully deleted from database (+25)")
    elif hist_count > 0:
        feedback_parts.append(f"Failed to delete {hist_count} historical records from database")
    else:
        feedback_parts.append("Could not verify database state (model error)")

    # 4. Safety/Preservation Verification (25 pts)
    # Active count in DB should match expected (2)
    preserved = result.get("db_active_names_preserved", False)
    if preserved:
        score += 25
        feedback_parts.append("Active records (2024+) correctly preserved in database (+25)")
    else:
        feedback_parts.append("CRITICAL: Active/Current flight plans were deleted or modified!")

    # Anti-gaming check
    if not result.get("archive_created_during_task", False) and result.get("archive_exists"):
        feedback_parts.append("WARNING: Archive file timestamp indicates it was not created during this task session.")
        # Deduct points or fail? Let's cap score.
        score = min(score, 40)

    total_score = min(100, score)
    passed = total_score >= 70

    return {
        "passed": passed,
        "score": total_score,
        "feedback": "\n".join(feedback_parts)
    }