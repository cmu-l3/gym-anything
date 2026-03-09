#!/usr/bin/env python3
"""
Verifier for create_concept_map_type task.

Verification Criteria:
1. Concept Map Type "ASSOCIATED-WITH" exists (30 pts)
2. Name matches exactly (case-sensitive) (15 pts)
3. Description contains "associated" (20 pts)
4. Not retired (10 pts)
5. Not hidden (10 pts)
6. Count increased from initial state (Anti-gaming) (10 pts)
7. Created after task start time (Anti-gaming) (5 pts)

Pass Threshold: 55 points (Must at least exist with correct name and be active)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_concept_map_type(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    score = 0
    feedback_parts = []
    
    # Extract data
    found = result.get("found", False)
    map_type = result.get("map_type", {})
    task_start = result.get("task_start", 0)
    initial_count = result.get("initial_count", 0)
    current_count = result.get("current_count", 0)

    # 1. Existence (30 pts)
    if found:
        score += 30
        feedback_parts.append("Map type found")
    else:
        feedback_parts.append("Map type 'ASSOCIATED-WITH' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Exact Name Match (15 pts)
    actual_name = map_type.get("name", "")
    if actual_name == "ASSOCIATED-WITH":
        score += 15
        feedback_parts.append("Name matches exactly")
    else:
        feedback_parts.append(f"Name case mismatch ({actual_name})")

    # 3. Description (20 pts)
    description = map_type.get("description", "") or ""
    if "associated" in description.lower():
        score += 20
        feedback_parts.append("Description valid")
    elif len(description.strip()) > 0:
        score += 10 # Partial credit for having a description
        feedback_parts.append("Description present but generic")
    else:
        feedback_parts.append("Description empty")

    # 4. Not Retired (10 pts)
    if not map_type.get("retired", True):
        score += 10
        feedback_parts.append("Active (not retired)")
    else:
        feedback_parts.append("Map type is retired")

    # 5. Not Hidden (10 pts)
    if not map_type.get("isHidden", True):
        score += 10
        feedback_parts.append("Visible (not hidden)")
    else:
        feedback_parts.append("Map type is hidden")

    # 6. Anti-gaming: Count Increased (10 pts)
    if current_count > initial_count:
        score += 10
        feedback_parts.append("Count increased")
    else:
        feedback_parts.append("Count did not increase")

    # 7. Anti-gaming: Creation Time (5 pts)
    created_ts = map_type.get("date_created_ts", 0)
    # Allow 5 minute grace period for clock skew
    if created_ts >= (task_start - 300):
        score += 5
        feedback_parts.append("Created during task")
    else:
        feedback_parts.append("Creation time verification failed")

    passed = score >= 55

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }