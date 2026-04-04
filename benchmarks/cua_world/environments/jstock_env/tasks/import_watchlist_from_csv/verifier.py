#!/usr/bin/env python3
"""
Verifier for import_watchlist_from_csv task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_watchlist(traj, env_info, task_info):
    """
    Verify that the healthcare stocks were imported into the JStock watchlist.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_stocks = set(metadata.get('target_stocks', ["JNJ", "PFE", "UNH", "ABT", "TMO", "ABBV", "MRK", "LLY"]))

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

    # Parsing result
    found_stocks = set(result.get('found_stocks', []))
    files_modified = result.get('files_modified_during_task', 0)
    found_count = len(found_stocks)
    total_targets = len(target_stocks)

    score = 0
    feedback_parts = []

    # Criterion 1: Stocks found (10 points per stock, max 80)
    matched_stocks = found_stocks.intersection(target_stocks)
    matched_count = len(matched_stocks)
    stock_score = matched_count * 10
    score += stock_score
    
    if matched_count == total_targets:
        feedback_parts.append(f"All {total_targets} healthcare stocks found in watchlist (+80)")
    else:
        feedback_parts.append(f"Found {matched_count}/{total_targets} stocks: {', '.join(matched_stocks)} (+{stock_score})")
        missing = target_stocks - matched_stocks
        feedback_parts.append(f"Missing: {', '.join(missing)}")

    # Criterion 2: Watchlist File Modification (Anti-gaming) (20 points)
    # The watchlist CSV must have been written to disk AFTER the task started.
    if files_modified > 0:
        score += 20
        feedback_parts.append("Watchlist files updated during task (+20)")
    else:
        feedback_parts.append("FAIL: Watchlist files were NOT modified/saved during task duration.")
        # If files weren't modified, the agent likely didn't save or didn't do anything.
        # Even if stocks are found (from pre-existing?), we should penalize severely or fail.
        # But in this setup, we wiped the watchlist in setup_task.sh, so if they are found,
        # the file MUST have been modified, unless the check logic is flawed.
        # We'll stick to the score penalty.
    
    # Final Pass/Fail
    passed = (score >= 60) and (files_modified > 0)

    if not passed and files_modified == 0:
        score = 0
        feedback_parts.append("Automatic FAIL: No changes detected on disk.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }