#!/usr/bin/env python3
"""
Verifier for hl7_enrichment_db_lookup task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hl7_enrichment_db_lookup(traj, env_info, task_info):
    """
    Verify the HL7 enrichment task.
    
    Scoring:
    - Channel Creation (20 pts): New channel created.
    - Channel Status (20 pts): Channel is deployed/started.
    - Enrichment Logic (60 pts): The 'live' test performed by export_result.sh passed.
      This confirms the agent implemented the DB lookup and insertion correctly.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Fields
    initial_count = result.get("initial_count", 0)
    current_count = result.get("current_count", 0)
    channel_id = result.get("channel_id", "")
    channel_status = result.get("channel_status", "UNKNOWN")
    live_verification_passed = result.get("live_verification_passed", False)
    verification_details = result.get("verification_details", "No details provided")

    score = 0
    feedback_parts = []

    # 3. Score: Channel Creation (20 pts)
    # Either count increased OR specific channel found by name
    if (current_count > initial_count) or (channel_id):
        score += 20
        feedback_parts.append("Channel created.")
    else:
        feedback_parts.append("No channel created.")

    # 4. Score: Channel Status (20 pts)
    if channel_status in ["STARTED", "DEPLOYED", "RUNNING"]:
        score += 20
        feedback_parts.append(f"Channel is active ({channel_status}).")
    elif channel_id:
        feedback_parts.append(f"Channel exists but status is {channel_status} (expected STARTED).")

    # 5. Score: Enrichment Logic (60 pts) - The Critical Check
    if live_verification_passed:
        score += 60
        feedback_parts.append("Dynamic DB lookup and enrichment verified successfully.")
    else:
        feedback_parts.append(f"Enrichment verification failed: {verification_details}")

    # Final tally
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }