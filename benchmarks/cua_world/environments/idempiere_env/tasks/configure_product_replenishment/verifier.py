#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_replenishment(traj, env_info, task_info):
    """
    Verify the replenishment configuration for Elm Tree.
    
    Criteria:
    1. Record exists in database for Elm Tree @ HQ Warehouse (30 pts)
    2. Replenish Type is 'Reorder below Minimum Level' (Type '1') (20 pts)
    3. Level Min is 25 (20 pts)
    4. Level Max is 100 (20 pts)
    5. Anti-gaming: Record created/updated after task start (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result from container
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
    feedback = []
    
    # Extract data
    record_found = result.get("record_found", False)
    replenish_type = result.get("replenish_type", "")
    level_min = float(result.get("level_min", 0))
    level_max = float(result.get("level_max", 0))
    created_ts = int(result.get("created_ts", 0))
    updated_ts = int(result.get("updated_ts", 0))
    task_start_ts = int(result.get("task_start_ts", 0))

    # Criterion 1: Record Found
    if record_found:
        score += 30
        feedback.append("Replenishment record found.")
    else:
        feedback.append("No replenishment record found for Elm Tree at HQ Warehouse.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Replenish Type
    # Type '1' corresponds to "Reorder below Minimum Level" in iDempiere standard AD
    if replenish_type == "1":
        score += 20
        feedback.append("Replenish Type correct (Reorder below Min).")
    else:
        feedback.append(f"Replenish Type incorrect. Expected '1', got '{replenish_type}'.")

    # Criterion 3: Level Min
    if abs(level_min - 25.0) < 0.1:
        score += 20
        feedback.append("Minimum Level correct (25).")
    else:
        feedback.append(f"Minimum Level incorrect. Expected 25, got {level_min}.")

    # Criterion 4: Level Max
    if abs(level_max - 100.0) < 0.1:
        score += 20
        feedback.append("Maximum Level correct (100).")
    else:
        feedback.append(f"Maximum Level incorrect. Expected 100, got {level_max}.")

    # Criterion 5: Anti-gaming (Timestamp check)
    # Check if created or updated after task start
    if created_ts >= task_start_ts or updated_ts >= task_start_ts:
        score += 10
        feedback.append("Record created/modified during task.")
    else:
        feedback.append("Record timestamp is before task start (pre-existing data used?).")

    # Final Result
    passed = (score >= 90) # Requires almost perfect execution
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }