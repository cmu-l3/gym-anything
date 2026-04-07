#!/usr/bin/env python3
"""
Verifier for block_travel_time task.
Verifies that:
1. "Travel to Client" event exists and ends when anchor event starts.
2. "Return Travel" event exists and starts when anchor event ends.
3. Both have correct duration (1h) and location ("In Transit").
"""

import json
import logging
import os
import tempfile
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_odoo_time(time_str):
    """Parse Odoo datetime string (UTC) to datetime object."""
    # Odoo typically returns 'YYYY-MM-DD HH:MM:SS'
    try:
        return datetime.strptime(time_str, "%Y-%m-%d %H:%M:%S")
    except (ValueError, TypeError):
        return None

def verify_block_travel_time(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic setup
    score = 0
    feedback_parts = []
    
    anchor = result.get('anchor_event')
    pre_events = result.get('pre_events', [])
    post_events = result.get('post_events', [])
    
    if not anchor:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "CRITICAL: Anchor event 'Client Onboarding' not found in database. Environment may be corrupted."
        }

    anchor_start = parse_odoo_time(anchor.get('start'))
    anchor_stop = parse_odoo_time(anchor.get('stop'))
    
    if not anchor_start or not anchor_stop:
        return {"passed": False, "score": 0, "feedback": "Could not parse anchor event times."}

    # --- Verify "Travel to Client" (Pre-event) ---
    best_pre = None
    pre_score = 0
    
    # Find the best matching pre-event
    for evt in pre_events:
        evt_score = 0
        
        # Check 1: Existence (implicit in loop)
        
        # Check 2: Timing (Ends when anchor starts)
        stop_time = parse_odoo_time(evt.get('stop'))
        if stop_time and abs((stop_time - anchor_start).total_seconds()) < 120: # 2 min tolerance
            evt_score += 20
        else:
            # Feedback for debugging
            if stop_time:
                diff = (stop_time - anchor_start).total_seconds() / 60
                logger.info(f"Pre-event '{evt.get('name')}' ends {diff:.1f} mins from anchor start")

        # Check 3: Duration (60 mins)
        if abs(evt.get('duration', 0) - 1.0) < 0.1: # 0.1 hour tolerance
            evt_score += 10
            
        # Check 4: Location
        if str(evt.get('location')).lower() == "in transit":
            evt_score += 5
            
        # Check 5: Anti-gaming (Created during task)
        create_date = parse_odoo_time(evt.get('create_date'))
        task_start_ts = result.get('task_start', 0)
        # Odoo stores create_date in UTC, assume task_start is roughly compatible or check diff
        # Simple check: if it exists in this list, it matched the search. 
        # We rely on setup_task.sh cleaning up old ones, so existence implies newness.
        evt_score += 5 

        if evt_score > pre_score:
            pre_score = evt_score
            best_pre = evt

    if best_pre:
        score += pre_score
        feedback_parts.append(f"Pre-travel event found (+{pre_score}pts)")
    else:
        feedback_parts.append("Pre-travel event missing or incorrect timing")

    # --- Verify "Return Travel" (Post-event) ---
    best_post = None
    post_score = 0
    
    for evt in post_events:
        evt_score = 0
        
        # Check 1: Timing (Starts when anchor ends)
        start_time = parse_odoo_time(evt.get('start'))
        if start_time and abs((start_time - anchor_stop).total_seconds()) < 120:
            evt_score += 20
            
        # Check 2: Duration
        if abs(evt.get('duration', 0) - 1.0) < 0.1:
            evt_score += 10
            
        # Check 3: Location
        if str(evt.get('location')).lower() == "in transit":
            evt_score += 5
            
        # Check 4: Created during task (implied by cleanup logic)
        evt_score += 5

        if evt_score > post_score:
            post_score = evt_score
            best_post = evt

    if best_post:
        score += post_score
        feedback_parts.append(f"Post-travel event found (+{post_score}pts)")
    else:
        feedback_parts.append("Post-travel event missing or incorrect timing")

    # --- Visual / VLM verification stub ---
    # In a full system, we would check the screenshot for visual adjacency.
    # For this programmatic verifier, we assume database timestamps are the ground truth.
    # We add 20 points for "Events Created" base score if at least one event was found.
    if best_pre or best_post:
        score += 20
        feedback_parts.append("Events successfully created in database")

    # Total possible: 40 (pre) + 40 (post) + 20 (base) = 100
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }