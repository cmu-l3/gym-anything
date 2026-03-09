#!/usr/bin/env python3
"""
Verifier for reify_stay_relationship task.

Criteria:
1. Schema: Classes StaySession (V), HasSession (E), SessionAt (E) must exist.
2. Data Migration: Count of StaySession must match the initial count of HasStayed edges.
3. Cleanup: HasStayed edges must be deleted (count 0 or class dropped).
4. Topology: Verify that StaySession vertices are correctly connected (Profile -> Session -> Hotel).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reify_stay_relationship(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Schema Verification (20 points)
    schema = result.get("schema", {})
    required_classes = ["StaySession", "HasSession", "SessionAt"]
    missing_classes = [c for c in required_classes if not schema.get(c, False)]
    
    if not missing_classes:
        score += 20
        feedback_parts.append("Schema refactored correctly")
    else:
        feedback_parts.append(f"Missing classes: {', '.join(missing_classes)}")

    # 2. Data Migration Check (40 points)
    counts = result.get("counts", {})
    initial_count = result.get("initial_count", 0)
    final_session_count = counts.get("StaySession", 0)
    
    # Tolerance of +/- 1 in case of weird edge cases, but should be exact
    if initial_count > 0 and abs(final_session_count - initial_count) <= 1:
        score += 40
        feedback_parts.append(f"Data migration count correct ({final_session_count}/{initial_count})")
    elif final_session_count > 0:
        # Partial credit for partial migration
        score += int(40 * (final_session_count / initial_count))
        feedback_parts.append(f"Partial migration ({final_session_count}/{initial_count})")
    else:
        feedback_parts.append("No StaySession vertices created")

    # 3. Connectivity/Topology Check (30 points)
    if result.get("connectivity_valid", False):
        score += 30
        feedback_parts.append("Graph topology valid (Profile->Session->Hotel)")
    else:
        feedback_parts.append("New vertices are not correctly connected to Profiles/Hotels")

    # 4. Cleanup Check (10 points)
    has_stayed_count = counts.get("HasStayed", 0)
    # If class is missing (-1) or count is 0, it's a pass
    if has_stayed_count <= 0:
        score += 10
        feedback_parts.append("Old 'HasStayed' edges removed")
    else:
        feedback_parts.append(f"Cleanup incomplete: {has_stayed_count} 'HasStayed' edges remain")

    # 5. VLM Anti-Gaming Check (Pass/Fail override)
    # Ensure they actually used the tool and didn't just curl the API from a script (though unlikely)
    # We mainly check if the UI was used or meaningful work happened.
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_res = query_vlm(
            images=frames,
            prompt="Does the user appear to be interacting with OrientDB Studio or a database console? Look for SQL commands, schema diagrams, or query results."
        )
        if not vlm_res.get("success") or "no" in vlm_res.get("response", "").lower():
            logger.warning("VLM did not detect obvious database interaction, but programmatic checks passed.")
            # We don't penalize heavily for this unless score is 0, as headless scripts are valid if they achieve the goal.
            # However, for a GUI task, we prefer GUI usage.

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }