#!/usr/bin/env python3
"""
Verifier for delete_watchlist task.

Checks if the 'Energy Stocks' directory was deleted while others remain.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_watchlist(traj, env_info, task_info):
    """
    Verify that:
    1. 'Energy Stocks' watchlist is gone.
    2. 'My Watchlist' and 'Tech Stocks' remain.
    3. The total number of watchlists decreased.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results from container
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
    
    # Extract data
    energy_exists = result.get("energy_stocks_exists", True)
    my_watchlist_exists = result.get("my_watchlist_exists", False)
    tech_exists = result.get("tech_stocks_exists", False)
    initial_count = result.get("initial_count", 3)
    remaining_count = result.get("remaining_count", 3)

    # Criterion 1: Energy Stocks Deleted (40 pts)
    if not energy_exists:
        score += 40
        feedback_parts.append("Success: 'Energy Stocks' watchlist deleted.")
    else:
        feedback_parts.append("Fail: 'Energy Stocks' watchlist still exists.")

    # Criterion 2: Others Preserved (40 pts total)
    if my_watchlist_exists:
        score += 20
        feedback_parts.append("'My Watchlist' preserved.")
    else:
        feedback_parts.append("Fail: 'My Watchlist' was deleted accidentally.")

    if tech_exists:
        score += 20
        feedback_parts.append("'Tech Stocks' preserved.")
    else:
        feedback_parts.append("Fail: 'Tech Stocks' was deleted accidentally.")

    # Criterion 3: Count sanity check (10 pts)
    # Ideally should be 2. If user created extra or deleted extra, this catches it.
    if remaining_count == 2:
        score += 10
        feedback_parts.append("Correct number of watchlists remaining (2).")
    elif remaining_count < 2:
        feedback_parts.append(f"Warning: Too few watchlists remaining ({remaining_count}).")
    elif remaining_count > 2:
        feedback_parts.append(f"Warning: Too many watchlists remaining ({remaining_count}).")

    # Criterion 4: Anti-gaming / Action verification (10 pts)
    if remaining_count < initial_count:
        score += 10
        feedback_parts.append("Confirmed reduction in watchlist count.")
    
    # Optional VLM check for context (tie-breaker or confirmation)
    # We only query VLM if score is borderline or to confirm UI interaction
    # Here, filesystem is authoritative, but we'll use VLM to verify intent if needed.
    # For now, we trust the robust filesystem check.
    
    passed = score >= 70 and (not energy_exists) and my_watchlist_exists and tech_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }