#!/usr/bin/env python3
"""
Verifier for batch_tag_urgent_cases task.

Scoring Criteria:
1. High Priority Case 1 Tagged: 30 pts
2. High Priority Case 2 Tagged: 30 pts
3. Low Priority Case Untouched: 30 pts
4. No unintended changes (Status/Title): 10 pts
5. VLM Trajectory Check: Verify search and navigation behavior

Pass Threshold: 90 points (Must get the logic right)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGET_TAG = "expedite-review"

def verify_batch_tagging(traj, env_info, task_info):
    """
    Verify that urgent cases were tagged and routine cases were ignored.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    cases = result.get('cases_analyzed', [])
    if not cases:
        return {"passed": False, "score": 0, "feedback": "No cases found for analysis. Setup or Export failed."}

    score = 0
    feedback_parts = []
    collateral_damage = False

    # 2. Score based on API state
    high_priority_hits = 0
    low_priority_misses = 0
    
    for case in cases:
        priority = case.get('priority')
        tags = case.get('tags', [])
        case_id = case.get('id')
        
        has_target_tag = TARGET_TAG in tags
        
        if priority == "High":
            if has_target_tag:
                score += 30
                high_priority_hits += 1
                feedback_parts.append(f"✅ High priority case {case_id} tagged correctly")
            else:
                feedback_parts.append(f"❌ High priority case {case_id} MISSED tag")
        
        elif priority == "Low":
            if not has_target_tag:
                score += 30
                feedback_parts.append(f"✅ Low priority case {case_id} correctly ignored")
            else:
                low_priority_misses += 1
                feedback_parts.append(f"❌ Low priority case {case_id} WRONGLY tagged")
        
        # Check for collateral damage (status changed from ACTIVE)
        if case.get('status') != 'ACTIVE':
            collateral_damage = True
            feedback_parts.append(f"⚠️ Case {case_id} status modified (unexpected)")

    # 3. Bonus for clean execution
    if not collateral_damage and high_priority_hits == 2 and low_priority_misses == 0:
        score += 10
        feedback_parts.append("✅ No unintended modifications (+10 pts)")
    
    # 4. VLM Trajectory Verification
    # Ensure they didn't just use a script but actually navigated
    frames = sample_trajectory_frames(traj, n=4)
    if frames and env_info.get('query_vlm'):
        vlm_res = query_vlm(
            prompt="Does this sequence show a user searching for items and visiting multiple case detail pages? "
                   "Look for a search results list and multiple different case IDs or titles.",
            images=frames
        )
        if not vlm_res.get('parsed', {}).get('yes_no_answer', True):
            # We don't deduct points heavily, but we warn
            feedback_parts.append("⚠️ VLM did not clearly observe search/navigation workflow")

    return {
        "passed": score >= 90,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }