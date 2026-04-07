#!/usr/bin/env python3
"""
Verifier for content_based_routing task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_content_based_routing(traj, env_info, task_info):
    """
    Verify creation of a multi-destination channel with content-based filtering.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # Extract Data
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    channel_name = result.get('channel_name', '')
    channel_status = result.get('channel_status', 'UNKNOWN')
    listen_port = result.get('listen_port', '')
    dest_count = result.get('destination_count', 0)
    
    routing = result.get('routing_test', {})
    adt_ok = routing.get('adt_success', False)
    orm_ok = routing.get('orm_success', False)
    oru_ok = routing.get('oru_success', False)
    
    adt_bad = routing.get('adt_contamination', False)
    orm_bad = routing.get('orm_contamination', False)
    oru_bad = routing.get('oru_contamination', False)

    score = 0
    feedback_parts = []

    # 1. Channel Creation (10 pts)
    if current_count > initial_count and channel_name:
        score += 10
        feedback_parts.append(f"Channel created: '{channel_name}'")
    else:
        feedback_parts.append("No new channel created")

    # 2. Channel Config (20 pts)
    # Port
    if listen_port == '6661':
        score += 10
        feedback_parts.append("Listening on correct port 6661")
    else:
        feedback_parts.append(f"Incorrect port: {listen_port} (expected 6661)")
    
    # Destinations (At least 3)
    if dest_count >= 3:
        score += 10
        feedback_parts.append(f"Destinations configured: {dest_count}")
    else:
        feedback_parts.append(f"Insufficient destinations: {dest_count} (expected 3)")

    # 3. Status (10 pts)
    if channel_status in ['STARTED', 'DEPLOYED', 'RUNNING']:
        score += 10
        feedback_parts.append("Channel is deployed and running")
    else:
        feedback_parts.append(f"Channel status: {channel_status}")

    # 4. Routing Logic (45 pts - 15 per type)
    # ADT
    if adt_ok and not adt_bad:
        score += 15
        feedback_parts.append("ADT routing confirmed")
    elif adt_ok:
        score += 5
        feedback_parts.append("ADT routing works but has contamination")
    else:
        feedback_parts.append("ADT routing failed")

    # ORM
    if orm_ok and not orm_bad:
        score += 15
        feedback_parts.append("ORM routing confirmed")
    elif orm_ok:
        score += 5
        feedback_parts.append("ORM routing works but has contamination")
    else:
        feedback_parts.append("ORM routing failed")

    # ORU
    if oru_ok and not oru_bad:
        score += 15
        feedback_parts.append("ORU routing confirmed")
    elif oru_ok:
        score += 5
        feedback_parts.append("ORU routing works but has contamination")
    else:
        feedback_parts.append("ORU routing failed")

    # 5. Global Cleanliness (15 pts)
    if (adt_ok and orm_ok and oru_ok) and (not adt_bad and not orm_bad and not oru_bad):
        score += 15
        feedback_parts.append("Perfect routing isolation (no cross-contamination)")

    passed = score >= 60 and (adt_ok or orm_ok or oru_ok)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }