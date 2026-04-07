#!/usr/bin/env python3
"""
Verifier for Fix & Verify Tracking Task
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_tracking(traj, env_info, task_info):
    """
    Verifies that the tracking code was fixed and a visit was recorded.
    
    Scoring Breakdown (100 pts total):
    - Code: Tracker URL set to localhost (20 pts)
    - Code: Site ID set to 1 (20 pts)
    - Code: trackPageView uncommented (15 pts)
    - Code: Heartbeat timer added with 10s (20 pts)
    - Functional: Visit recorded in DB (25 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    
    # 1. Check Code Fixes
    if result.get('has_localhost', False):
        score += 20
        feedback_parts.append("Tracker URL Correct (+20)")
    else:
        feedback_parts.append("Tracker URL Incorrect (must be localhost)")

    if result.get('has_site_id_1', False):
        score += 20
        feedback_parts.append("Site ID Correct (+20)")
    else:
        feedback_parts.append("Site ID Incorrect (must be 1)")

    if result.get('has_track_pageview', False):
        score += 15
        feedback_parts.append("PageView Tracking Enabled (+15)")
    else:
        feedback_parts.append("PageView Tracking Disabled")

    # 2. Check Heartbeat
    if result.get('heartbeat_value_10', False):
        score += 20
        feedback_parts.append("Heartbeat Timer Set to 10s (+20)")
    elif result.get('has_heartbeat', False):
        score += 10
        feedback_parts.append("Heartbeat Timer Present but Wrong Value (+10)")
    else:
        feedback_parts.append("Heartbeat Timer Missing")

    # 3. Check Functional Verification (End-to-End)
    if result.get('db_visit_found', False):
        score += 25
        feedback_parts.append("Visit Verified in Database (+25)")
    else:
        feedback_parts.append("No Visit Recorded in Database (Did you open the page?)")

    passed = (score >= 75)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }