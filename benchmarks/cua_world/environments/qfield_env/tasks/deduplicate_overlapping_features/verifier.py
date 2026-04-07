#!/usr/bin/env python3
"""
Verifier for QField Deduplication Task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deduplicate_overlapping_features(traj, env_info, task_info):
    """
    Verify that the 'LEGACY_DUPLICATE' feature was removed and the valid feature remains.
    """
    # Use copy_from_env to get the result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Parse DB analysis
    db_stats = result.get('db_analysis', {})
    if db_stats.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Database error: {db_stats['error']}"}

    rome_count = db_stats.get('rome_count', 0)
    has_legacy = db_stats.get('has_legacy_duplicate', False)
    has_valid = db_stats.get('has_valid_rome', False)

    score = 0
    feedback_parts = []

    # Criterion 1: Duplicate Removed (40 pts)
    if not has_legacy:
        score += 40
        feedback_parts.append("Success: 'LEGACY_DUPLICATE' feature removed.")
    else:
        feedback_parts.append("Fail: 'LEGACY_DUPLICATE' feature still exists.")

    # Criterion 2: Rome Count is Correct (40 pts)
    # Ideally count should be 1. If it's 0, they deleted everything. If 2, they did nothing.
    if rome_count == 1:
        score += 40
        feedback_parts.append("Success: Exactly one 'Rome' feature remains.")
    elif rome_count == 0:
        feedback_parts.append("Fail: All 'Rome' features were deleted.")
    else:
        feedback_parts.append(f"Fail: Found {rome_count} 'Rome' features (expected 1).")

    # Criterion 3: Valid Feature Preserved (20 pts)
    # This overlaps with count=1, but specifically checks we didn't delete the good one
    # and keep the bad one (which would result in count=1, has_legacy=True).
    if has_valid:
        score += 20
        feedback_parts.append("Success: Valid 'Rome' feature preserved.")
    else:
        feedback_parts.append("Fail: Valid 'Rome' feature is missing.")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }