#!/usr/bin/env python3
"""
Verifier for create_virtual_feed_aggregation task.
Verifies that the agent created a Virtual Feed that sums three specific source feeds.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_virtual_feed_aggregation(traj, env_info, task_info):
    """
    Verifies the creation and configuration of the Virtual Feed.
    
    Criteria:
    1. Feed 'GuestHouse_Total' exists (20 pts)
    2. Engine is 'Virtual' (ID 7) (30 pts)
    3. Value is correct (sum of sources) (20 pts)
    4. Process list indicates aggregation (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_val = 3851.5  # 150.5 + 1200.2 + 2500.8
    tolerance = metadata.get('tolerance', 0.1)
    
    # Load result
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

    score = 0
    feedback = []
    
    # 1. Feed Exists
    if result.get('feed_found'):
        score += 20
        feedback.append("Feed 'GuestHouse_Total' found.")
    else:
        feedback.append("Feed 'GuestHouse_Total' NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Correct Engine (Virtual Feed = 7)
    engine = result.get('feed_engine')
    # ID 7 is standard for Virtual Feed in Emoncms, sometimes labeled 'Virtual'
    if engine == 7 or str(engine) == "7":
        score += 30
        feedback.append("Engine is correct (Virtual).")
    else:
        feedback.append(f"Incorrect Engine: {engine} (Expected Virtual/7).")

    # 3. Correct Value (Sum check)
    try:
        val = float(result.get('feed_value', 0))
        diff = abs(val - expected_val)
        if diff <= tolerance:
            score += 20
            feedback.append(f"Feed value correct ({val}).")
        else:
            feedback.append(f"Feed value incorrect: {val} (Expected ~{expected_val}).")
    except:
        feedback.append("Could not parse feed value.")

    # 4. Logic/Process List Check
    # We look for evidence of summation.
    # The raw process list might look like "1:10,6:12,6:13" 
    # (Source Feed:ID, + Feed:ID, + Feed:ID)
    # We won't strictly validate IDs (since they change), but we check for complexity.
    raw_process = result.get('raw_process_list', '')
    
    # In Emoncms Virtual Feeds:
    # Process 'Source Feed' usually has ID ~ 'Source' or special handling?
    # Actually, often mapped to process input IDs.
    # '+ Feed' is ID 6.
    # We expect at least two additions or similar operations.
    
    if len(raw_process) > 5: # Basic check that it's not empty
        # Check for multiple steps (commas usually separate steps)
        steps = raw_process.split(',')
        if len(steps) >= 3:
            score += 30
            feedback.append("Process list has sufficient steps for aggregation.")
        elif len(steps) >= 1:
            score += 10
            feedback.append("Process list exists but seems too short for 3-feed sum.")
        else:
            feedback.append("Process list logic unclear.")
    else:
        feedback.append("Process list is empty/missing.")

    # Final tally
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }