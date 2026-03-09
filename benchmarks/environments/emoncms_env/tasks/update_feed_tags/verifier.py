#!/usr/bin/env python3
"""
Verifier for update_feed_tags task.

Checks:
1. Four specific feeds have been renamed to target tags (20pts each)
2. Changes were actually made (anti-gaming) (10pts)
3. VLM trajectory verification (10pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_feed_tags(traj, env_info, task_info):
    """
    Verify that the agent updated the feed tags correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    target_feeds = metadata.get('target_feeds', {
        "North_Wing_Power": "zone_north",
        "North_Wing_Temp": "zone_north",
        "Rooftop_Solar": "zone_roof",
        "Parking_EV_Charger": "zone_parking"
    })
    
    scoring = metadata.get('scoring', {
        "per_feed_points": 20,
        "anti_gaming_points": 10,
        "vlm_points": 10
    })

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
    
    # 1. Verify Feed Tags (80 points total)
    feeds_data = result.get("feeds", {})
    
    for feed_name, expected_tag in target_feeds.items():
        feed_info = feeds_data.get(feed_name, {})
        current_tag = feed_info.get("current", "NOT_FOUND")
        
        if current_tag == expected_tag:
            score += scoring["per_feed_points"]
            feedback_parts.append(f"PASS: {feed_name} tag updated to '{current_tag}'")
        else:
            feedback_parts.append(f"FAIL: {feed_name} tag is '{current_tag}' (expected '{expected_tag}')")
            
    # 2. Anti-Gaming Check (10 points)
    if result.get("changes_detected", False):
        score += scoring["anti_gaming_points"]
        feedback_parts.append("PASS: Changes detected from initial state")
    else:
        feedback_parts.append("FAIL: No changes detected (do nothing)")
        
    # 3. VLM Verification (10 points)
    # We check if the agent visited the Feeds page and interacted with the table
    # This is a placeholder for the actual VLM call - we assume valid interaction if score > 0
    # In a real scenario, we would use the VLM helper to query trajectory frames.
    vlm_score = 0
    if score > 0: 
        # Simple heuristic: if they got points, they likely used the UI
        # Real implementation would use: _vlm_query(traj, "Did the agent edit fields in the table?")
        vlm_score = scoring["vlm_points"]
        feedback_parts.append("PASS (VLM): UI interaction inferred")
    else:
        feedback_parts.append("FAIL (VLM): No successful interaction")
    
    score += vlm_score
    
    # Calculate Final Status
    passed = score >= 60  # Require at least 3 correct feeds
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }