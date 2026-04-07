#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_define_project_activities(traj, env_info, task_info):
    """
    Verify that the agent added the correct activities to the project.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_activities = set(a.lower() for a in metadata.get('required_activities', []))
    
    # 2. Retrieve Result JSON
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

    # 3. Check Verification Criteria
    score = 0
    feedback_parts = []
    
    # Criterion 1: Project must exist (Sanity check) - 0 pts (pre-requisite)
    if not result.get('project_found'):
        return {"passed": False, "score": 0, "feedback": "Target project was deleted or not found."}

    # Get actual activities found
    actual_activities_raw = result.get('activities', [])
    actual_activities = set(a.lower() for a in actual_activities_raw)
    
    logger.info(f"Required: {required_activities}")
    logger.info(f"Actual: {actual_activities}")

    # Criterion 2: Check for each required activity (20 pts each)
    found_count = 0
    missing_activities = []
    
    for req in required_activities:
        if req in actual_activities:
            score += 20
            found_count += 1
        else:
            missing_activities.append(req)

    if found_count == len(required_activities):
        feedback_parts.append(f"All {found_count} specific activities found.")
    else:
        feedback_parts.append(f"Found {found_count}/{len(required_activities)} activities.")
        feedback_parts.append(f"Missing: {', '.join(missing_activities)}")

    # Criterion 3: Exact Count (20 pts)
    # We want exactly 4 activities. If there are extra garbage ones, deduct points or fail this criterion.
    if len(actual_activities) == 4 and found_count == 4:
        score += 20
        feedback_parts.append("Correct total count (4).")
    elif len(actual_activities) > 4:
        feedback_parts.append(f"Too many activities defined (Found {len(actual_activities)}, expected 4).")
    elif len(actual_activities) < 4:
        # Already handled by individual checks, but explicitly fail the count bonus
        pass

    # 4. Final Assessment
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }