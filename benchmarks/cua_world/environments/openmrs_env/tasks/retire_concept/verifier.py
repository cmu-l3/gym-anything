#!/usr/bin/env python3
"""
Verifier for retire_concept task.
Verifies that the OpenMRS concept was retired with the correct reason.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retire_concept(traj, env_info, task_info):
    """
    Verify the concept was retired correctly in the database.
    
    Criteria:
    1. Concept still exists (not purged) - 10 pts
    2. Concept is marked as retired (retired=1) - 40 pts
    3. Retire reason contains '2026 Guidelines' - 30 pts
    4. Retired timestamp is after task start (anti-gaming) - 20 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Extract data
    concept_exists = result.get('concept_exists', False)
    is_retired = result.get('is_retired', False)
    retire_reason = result.get('retire_reason', "")
    retired_during_task = result.get('retired_during_task', False)
    
    score = 0
    feedback_parts = []
    
    # 1. Existence Check (10 pts)
    if concept_exists:
        score += 10
        feedback_parts.append("Concept found in DB")
    else:
        return {"passed": False, "score": 0, "feedback": "Concept was purged/deleted instead of retired!"}

    # 2. Retired Status (40 pts)
    if is_retired:
        score += 40
        feedback_parts.append("Concept is retired")
    else:
        feedback_parts.append("Concept is NOT retired")
        
    # 3. Reason Check (30 pts)
    required_fragment = task_info.get('metadata', {}).get('required_retire_reason_fragment', "2026 Guidelines")
    if required_fragment.lower() in retire_reason.lower():
        score += 30
        feedback_parts.append(f"Reason correct ('{retire_reason}')")
    else:
        feedback_parts.append(f"Reason incorrect (Found: '{retire_reason}', Expected fragment: '{required_fragment}')")

    # 4. Anti-gaming / Timestamp Check (20 pts)
    if is_retired:
        if retired_during_task:
            score += 20
            feedback_parts.append("Modification occurred during task")
        else:
            feedback_parts.append("Modification timestamp check failed (stale data?)")

    # Final logic
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }