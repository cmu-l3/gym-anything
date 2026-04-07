#!/usr/bin/env python3
"""
Verifier for consolidate_duplicate_events_scolv task.

Checks:
1. Exactly one event remains in the target time window (40 points)
2. Surviving event contains all original origins via OriginReference (40 points)
3. Event has a valid preferred origin (10 points)
4. State modified during task execution (10 points)
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_events(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Database export error: {result['error']}"}

    initial_origins = result.get('initial_origins', [])
    events = result.get('events', [])

    if len(initial_origins) < 2:
        logger.warning(f"Expected at least 2 initial origins, found {len(initial_origins)}")

    if not events:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: No events found in target window. All events were deleted instead of merged."
        }

    score = 0
    feedback = []

    # Criterion 1: Exactly 1 event remains
    if len(events) == 1:
        score += 40
        feedback.append("SUCCESS: Exactly one event remains in the target window.")
    elif len(events) > 1:
        feedback.append(f"FAIL: {len(events)} events still exist. Events were not merged.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    surviving_event = events[0]
    referenced_origins = surviving_event.get('referenced_origins', [])

    # Criterion 2: Origins consolidated
    missing_origins = [o for o in initial_origins if o not in referenced_origins]
    
    if not missing_origins and len(initial_origins) >= 2:
        score += 40
        feedback.append("SUCCESS: Surviving event contains all original origins.")
    else:
        feedback.append(f"FAIL: Surviving event is missing origins. Expected {initial_origins}, Found {referenced_origins}.")

    # Criterion 3: Valid Event State
    if surviving_event.get('preferred_origin_id'):
        score += 10
        feedback.append("SUCCESS: Surviving event has a preferred origin.")
    else:
        feedback.append("FAIL: Surviving event is missing a preferred origin.")

    # Criterion 4: Modification / State Delta
    # If there is 1 event left that successfully consolidated >= 2 origins, 
    # then the state was definitely modified appropriately during the task.
    if not missing_origins and len(events) == 1 and len(initial_origins) >= 2:
        score += 10
        feedback.append("SUCCESS: Event database modified appropriately.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }