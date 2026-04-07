#!/usr/bin/env python3
"""
Verifier for retime_animation_breakdown task.

Strategy:
1. Verify 24 PNG files exist.
2. Verify files were created during the task.
3. Verify the "rhythm" of the animation by checking image differences between consecutive frames.
   The task requires specific Holds (identical consecutive frames) and Changes.

Timing Chart Requirement:
- Frames 1-4: Hold (Diffs 1-2, 2-3, 3-4 should be ~0)
- Transition 4-5: Change (Diff > 0)
- Frames 5-6: Hold (Diff 5-6 ~0)
- Transition 6-7: Change (Diff > 0)
- Frames 7-8: Hold (Diff 7-8 ~0)
- Transition 8-9: Change (Diff > 0)
- Frames 9-10: Hold (Diff 9-10 ~0)
- Transition 10-11: Change (Diff > 0)
- Frames 11-20: Hold (Diffs 11...19 should be ~0)
- Transition 20-21: Change (Diff > 0)
- Frames 21-24: Hold (Diffs 21...23 should be ~0)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retime_animation_breakdown(traj, env_info, task_info):
    # 1. Retrieve result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

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

    # 2. Scoring Variables
    score = 0
    feedback = []
    
    total_files = result.get('total_files', 0)
    new_files = result.get('files_created_during_task', 0)
    diff_profile = result.get('diff_profile', [])

    # Criteria 1: File Count (24 frames) [20 pts]
    if total_files >= 24:
        score += 20
        feedback.append("Correct frame count (24+).")
    elif total_files > 0:
        score += int(20 * (total_files / 24))
        feedback.append(f"Incomplete frame count: {total_files}/24.")
    else:
        feedback.append("No output frames found.")
        return {"passed": False, "score": 0, "feedback": "No output files found."}

    # Criteria 2: Anti-Gaming (Timestamp) [10 pts]
    if new_files >= 24:
        score += 10
    elif new_files > 0:
        score += 5
        feedback.append("Some files were pre-existing or not newly rendered.")
    else:
        feedback.append("Files were not created during this task session.")

    # Criteria 3: Verify Timing Pattern [70 pts]
    # We define 'Hold' as diff < 1.0 (allow slight compression artifacts)
    # We define 'Change' as diff > 5.0
    HOLD_THRESH = 2.0
    CHANGE_THRESH = 5.0
    
    # Map of Expected Holds (Frame indices i where Frame i and i+1 should be identical)
    # Note: Frame indices in profile are 1-based.
    # 1-4 Hold -> Pairs (1,2), (2,3), (3,4) should be ~0
    # 5-6 Hold -> Pair (5,6) should be ~0
    # ...
    
    expected_holds = [1, 2, 3, 5, 7, 9] + list(range(11, 20)) + [21, 22, 23]
    expected_changes = [4, 6, 8, 10, 20] # Transitions: 4->5, 6->7, etc.

    pattern_score = 0
    total_checks = len(expected_holds) + len(expected_changes)
    
    # Analyze profile
    profile_map = {d['frame_idx']: d['diff_score'] for d in diff_profile}
    
    correct_holds = 0
    correct_changes = 0

    # Check Holds
    for idx in expected_holds:
        diff = profile_map.get(idx, -1)
        if diff != -1 and diff <= HOLD_THRESH:
            correct_holds += 1
        elif diff > HOLD_THRESH:
            feedback.append(f"Frame {idx}-{idx+1} should be a HOLD, but diff is {diff:.2f}")

    # Check Changes
    for idx in expected_changes:
        diff = profile_map.get(idx, -1)
        if diff != -1 and diff > HOLD_THRESH: # At least significant change, even if small
            correct_changes += 1
        elif diff != -1:
            feedback.append(f"Frame {idx}-{idx+1} should CHANGE, but looks identical (Hold).")

    # Calculate Pattern Score
    # We weight changes slightly higher as they define the rhythm
    
    if total_checks > 0:
        # 70 points distributed
        accuracy = (correct_holds + correct_changes) / total_checks
        pattern_pts = int(70 * accuracy)
        score += pattern_pts
        feedback.append(f"Timing Pattern Accuracy: {int(accuracy*100)}%")

    # Final Pass Check
    passed = score >= 60 and total_files >= 24
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }