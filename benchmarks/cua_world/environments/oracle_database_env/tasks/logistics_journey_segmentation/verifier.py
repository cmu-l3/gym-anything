#!/usr/bin/env python3
"""
Verifier for Logistics Journey Segmentation task.
Tests if the agent correctly solved the Gaps-and-Islands problem in SQL.

Criteria:
1. View JOURNEY_SEGMENTS exists (10 pts)
2. View has correct columns (10 pts)
3. Container 101 has 4 segments (Tests A-B-A logic) (25 pts)
4. Container 102 has 1 segment (Tests contiguous grouping) (10 pts)
5. Container 103 has 5 segments (Tests rapid switching) (15 pts)
6. A-B-A Logic explicitly verified (Transit->Customs->Transit) (20 pts)
7. CSV file exists and was created during task (10 pts)

Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_logistics_journey_segmentation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Retrieve result
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_path)
            with open(result_path, "r") as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # 1. View Exists (10 pts)
    if result.get("view_exists"):
        score += 10
        feedback.append("View JOURNEY_SEGMENTS created (+10)")
    else:
        feedback.append("View JOURNEY_SEGMENTS not found (0)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Column Structure (10 pts)
    required_cols = {'CONTAINER_ID', 'SEGMENT_ID', 'STATUS', 'START_TIME', 'END_TIME', 'DURATION_MINS'}
    actual_cols = set(result.get("view_columns", []))
    if required_cols.issubset(actual_cols):
        score += 10
        feedback.append("Correct columns (+10)")
    else:
        missing = required_cols - actual_cols
        feedback.append(f"Missing columns: {missing} (0)")

    # 3. Logic Check: Container 101 (25 pts)
    # Expected: 4 segments (Transit, Customs, Transit, Docked)
    c101 = result.get("segments_101", 0)
    if c101 == 4:
        score += 25
        feedback.append("Container 101 segmentation correct (4 segments) (+25)")
    else:
        feedback.append(f"Container 101 segmentation incorrect. Found {c101}, expected 4. (Gap-and-island logic failed)")

    # 4. Logic Check: Container 102 (10 pts)
    # Expected: 1 segment (All docked)
    c102 = result.get("segments_102", 0)
    if c102 == 1:
        score += 10
        feedback.append("Container 102 segmentation correct (+10)")
    else:
        feedback.append(f"Container 102 failed. Found {c102}, expected 1")

    # 5. Logic Check: Container 103 (15 pts)
    # Expected: 5 segments
    c103 = result.get("segments_103", 0)
    if c103 == 5:
        score += 15
        feedback.append("Container 103 segmentation correct (+15)")
    else:
        feedback.append(f"Container 103 failed. Found {c103}, expected 5")

    # 6. Explicit A-B-A Logic (20 pts)
    if result.get("correct_logic_aba"):
        score += 20
        feedback.append("A-B-A transition logic verified (+20)")
    else:
        feedback.append("A-B-A logic check failed (Sequences merged incorrectly)")

    # 7. CSV Export (10 pts)
    if result.get("csv_exists") and result.get("csv_created_during_task"):
        score += 10
        feedback.append("CSV export successful (+10)")
    else:
        feedback.append("CSV file missing or stale")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }