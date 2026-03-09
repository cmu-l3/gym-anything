#!/usr/bin/env python3
"""
Verifier for global_metadata_legend_config task.

Scoring Breakdown (100 points total):
1. Legend Set "RMNCH Standard Scorecard" exists (20 pts)
2. Legend Set has exactly 3 items (15 pts)
3. Legend items cover correct ranges (0-50, 50-80, 80-100) (25 pts)
4. "Institutional delivery rate" indicator found and modified (20 pts)
5. Indicator is correctly linked to the new Legend Set (20 pts)

Pass Threshold: 60 points
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_global_metadata_legend_config(traj, env_info, task_info):
    """
    Verify that the Legend Set was created correctly and assigned to the Indicator.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Verify Legend Set Existence (20 pts)
    if result.get('legend_set_found'):
        score += 20
        feedback.append("Success: Legend Set 'RMNCH Standard Scorecard' created.")
    else:
        feedback.append("Fail: Legend Set 'RMNCH Standard Scorecard' not found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # 3. Verify Item Count (15 pts)
    count = result.get('legend_items_count', 0)
    if count == 3:
        score += 15
        feedback.append("Success: Correct number of legend items (3).")
    else:
        feedback.append(f"Partial: Found {count} legend items (expected 3).")

    # 4. Verify Thresholds (25 pts)
    # Expected ranges: 0-50, 50-80, 80-100
    # We allow slight flexibility (e.g., 50.1) but look for the specific boundaries.
    items = result.get('legend_items', [])
    
    # Extract ranges
    ranges = []
    for item in items:
        try:
            s = float(item.get('startValue', -1))
            e = float(item.get('endValue', -1))
            ranges.append((s, e))
        except:
            continue
    
    ranges.sort() # Sort by start value
    
    # Check for specific cutoffs
    has_0_50 = any(abs(r[0] - 0) < 1 and abs(r[1] - 50) < 1 for r in ranges)
    has_50_80 = any(abs(r[0] - 50) < 1 and abs(r[1] - 80) < 1 for r in ranges)
    has_80_100 = any(abs(r[0] - 80) < 1 and abs(r[1] - 100) < 1 for r in ranges) # End might be 100 or 100+

    if has_0_50 and has_50_80 and has_80_100:
        score += 25
        feedback.append("Success: Legend item ranges are correct (0-50, 50-80, 80-100).")
    elif len(ranges) == 3:
        # Partial credit if 3 items exist but ranges slightly off
        score += 10
        feedback.append(f"Partial: Ranges found {ranges} do not exactly match expected standard.")
    else:
        feedback.append("Fail: Legend item ranges are incorrect.")

    # 5. Verify Indicator Modification (20 pts)
    if result.get('indicator_found'):
        if result.get('indicator_updated_after_start'):
            score += 20
            feedback.append("Success: 'Institutional delivery rate' indicator was modified during task.")
        else:
            # If linked correctly but timestamp didn't update (unlikely), we might skip this
            # but usually modification updates timestamp. We'll give partial if linked.
            feedback.append("Warning: Indicator timestamp suggests it wasn't modified recently.")
    else:
        feedback.append("Fail: Target indicator not found.")

    # 6. Verify Linkage (20 pts)
    if result.get('linkage_correct'):
        score += 20
        feedback.append("Success: Indicator is correctly linked to the new Legend Set.")
    else:
        ls_id = result.get('legend_set_id')
        linked_id = result.get('indicator_linked_legend_set_id')
        feedback.append(f"Fail: Indicator not linked to correct legend set (Linked: {linked_id}, Expected: {ls_id}).")

    # Final Pass/Fail
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }