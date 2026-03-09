#!/usr/bin/env python3
"""
Verifier for robotstxt_blocking_simulation_audit task.

Scoring (100 points total):
1. Simulation Configured (40 pts): 'Travel' URLs found in blocked export with correct blocked status.
2. Precision Check (30 pts): Other URLs found in allowed export with 200 OK status.
3. Data Export (20 pts): Both CSV files exist and are valid.
4. Valid Domain (10 pts): Data is from books.toscrape.com.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_robotstxt_simulation(traj, env_info, task_info):
    """Verify the robots.txt simulation task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
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
    
    # 1. Data Export Existence (20 pts)
    # 10 pts per file
    blocked_exists = result.get("blocked_csv_exists", False) and result.get("blocked_csv_valid_timestamp", False)
    allowed_exists = result.get("allowed_csv_exists", False) and result.get("allowed_csv_valid_timestamp", False)
    
    if blocked_exists:
        score += 10
        feedback_parts.append("Blocked URLs CSV exported")
    else:
        feedback_parts.append("Blocked URLs CSV missing or old")
        
    if allowed_exists:
        score += 10
        feedback_parts.append("Allowed URLs CSV exported")
    else:
        feedback_parts.append("Allowed URLs CSV missing or old")

    # 2. Simulation Configured (40 pts)
    # Must have found travel URLs AND they must be blocked
    travel_found = result.get("blocked_travel_urls_found", 0)
    blocked_verified = result.get("blocked_status_verified", False)
    
    if travel_found > 0:
        if blocked_verified:
            score += 40
            feedback_parts.append(f"Success: {travel_found} 'Travel' URLs blocked by robots.txt")
        else:
            score += 10 # Found URLs but wrong status (maybe 200?)
            feedback_parts.append(f"Failed: {travel_found} 'Travel' URLs in export but NOT blocked (Status != Blocked)")
    else:
        feedback_parts.append("Failed: No 'Travel' URLs found in blocked export")

    # 3. Precision Check (30 pts)
    # Must have found other URLs and they must be 200 OK
    other_found = result.get("allowed_other_urls_found", 0)
    allowed_verified = result.get("allowed_status_verified", False)
    
    if other_found > 0:
        if allowed_verified:
            score += 30
            feedback_parts.append(f"Success: {other_found} other URLs allowed (200 OK)")
        else:
            score += 5
            feedback_parts.append(f"Other URLs found but not 200 OK")
    else:
        feedback_parts.append("No allowed URLs found in export")

    # 4. Valid Domain (10 pts)
    # Implied by having found URLs matching our filters in the Python script
    if travel_found > 0 or other_found > 0:
        score += 10
        feedback_parts.append("Domain verified")

    # Check for SF running (small penalty if not, but not critical if exports exist)
    sf_running = result.get("sf_running", False)
    if not sf_running and score > 0:
        feedback_parts.append("(Screaming Frog closed after task)")

    passed = score >= 70 and blocked_verified and allowed_verified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }