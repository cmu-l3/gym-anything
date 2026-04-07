#!/usr/bin/env python3
"""
Verifier for configure_advanced_set_types task.

Evaluates the exact set configurations retrieved from the wger database:
- Squat set 1 and 2 should be Warm-up (type=2)
- Leg Extension set 4 should be Drop set (type=4)
- Other sets must remain Normal (type=1)
- Counts must strictly remain 5 and 4 respectively.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_advanced_sets(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Fetch result JSON from the container
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

    if not result.get('exists', False):
        return {"passed": False, "score": 0, "feedback": "Target routine 'Hypertrophy Block' not found."}

    squat_sets = result.get('squat_sets', [])
    extension_sets = result.get('extension_sets', [])
    
    logger.info(f"Squat sets config (Types): {squat_sets}")
    logger.info(f"Extension sets config (Types): {extension_sets}")

    score = 0
    feedback_parts = []
    
    # 1. Evaluate Barbell Squat Warm-ups (Expected: Type 2 for index 0 and 1)
    if len(squat_sets) >= 1 and squat_sets[0] == 2:
        score += 15
        feedback_parts.append("Squat Set 1 updated to Warm-up")
    else:
        feedback_parts.append("Squat Set 1 is incorrect")

    if len(squat_sets) >= 2 and squat_sets[1] == 2:
        score += 15
        feedback_parts.append("Squat Set 2 updated to Warm-up")
    else:
        feedback_parts.append("Squat Set 2 is incorrect")

    # 2. Evaluate Leg Extension Drop Set (Expected: Type 4 for index 3)
    if len(extension_sets) >= 4 and extension_sets[3] == 4:
        score += 30
        feedback_parts.append("Extension Set 4 updated to Drop set")
    else:
        feedback_parts.append("Extension Set 4 is incorrect")

    # 3. Check preservation of Working Sets (Must remain Normal, Type 1)
    squat_working_ok = len(squat_sets) >= 5 and all(s == 1 for s in squat_sets[2:5])
    if squat_working_ok:
        score += 15
        feedback_parts.append("Squat working sets preserved as Normal")
    else:
        feedback_parts.append("Squat working sets were modified or lost")

    extension_working_ok = len(extension_sets) >= 3 and all(s == 1 for s in extension_sets[0:3])
    if extension_working_ok:
        score += 15
        feedback_parts.append("Extension working sets preserved as Normal")
    else:
        feedback_parts.append("Extension working sets were modified or lost")

    # 4. Check that no extra sets were added / deleted
    counts_ok = len(squat_sets) == 5 and len(extension_sets) == 4
    if counts_ok:
        score += 10
        feedback_parts.append("Exact set counts maintained")
    else:
        feedback_parts.append(f"Set counts altered (Squats: {len(squat_sets)}, Extensions: {len(extension_sets)})")

    # Pass condition: All specific set type modifications achieved and no collateral damage
    passed = (score >= 70 and squat_working_ok and extension_working_ok)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }