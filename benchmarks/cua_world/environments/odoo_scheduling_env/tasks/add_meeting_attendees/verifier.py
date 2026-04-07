#!/usr/bin/env python3
"""
Verifier for add_meeting_attendees task.

Verification Logic:
1. Check if "Product Roadmap Planning" event exists.
2. Verify it is the SAME event (ID match) as baseline (Anti-Gaming: Do not delete & recreate).
3. Verify newly added attendees: "Henry Kim", "Isabel Santos".
4. Verify original attendees retained: "Alice Johnson", "David Chen", "Emma Thompson".

Scoring:
- Event exists: 10 pts
- Event ID matches baseline (not recreated): 10 pts
- Henry Kim added: 20 pts
- Isabel Santos added: 20 pts
- Alice Johnson retained: 10 pts
- David Chen retained: 10 pts
- Emma Thompson retained: 10 pts
- VLM Trajectory (work performed): 10 pts
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_meeting_attendees(traj, env_info, task_info):
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

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # Metadata targets
    metadata = task_info.get("metadata", {})
    target_added = metadata.get("attendees_to_add", ["Henry Kim", "Isabel Santos"])
    target_retained = metadata.get("attendees_to_retain", ["Alice Johnson", "David Chen", "Emma Thompson"])
    
    # 1. Event Existence (10 pts)
    if not result.get("final_event_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Event 'Product Roadmap Planning' not found in calendar."
        }
    score += 10
    feedback_parts.append("Event found")

    # 2. Anti-Gaming: Event Identity (10 pts)
    # Ensure the agent didn't just delete the old one and make a new one
    baseline_id = result.get("baseline_event_id")
    final_id = result.get("final_event_id")
    baseline_date = result.get("baseline_create_date")
    final_date = result.get("final_create_date")

    if baseline_id == final_id and baseline_date == final_date:
        score += 10
        feedback_parts.append("Event modified correctly (not recreated)")
    else:
        feedback_parts.append("Event was recreated (ID/Date mismatch) - penalty applied")

    # Get current attendee list
    current_attendees = result.get("attendee_names", [])
    
    # 3. New Attendees (20 pts each)
    for name in target_added:
        if name in current_attendees:
            score += 20
            feedback_parts.append(f"Added {name}")
        else:
            feedback_parts.append(f"Missing {name}")

    # 4. Retained Attendees (10 pts each)
    for name in target_retained:
        if name in current_attendees:
            score += 10
            feedback_parts.append(f"Retained {name}")
        else:
            feedback_parts.append(f"Removed {name}")

    # 5. VLM Trajectory Check (10 pts)
    # Simple check: did we get screenshots? In a real system, we'd run VLM here.
    # For this robust deterministic verifier, we'll award points if the task was attempted.
    # We rely on the fact that if they got the data right, they likely used the UI.
    if traj:
        score += 10
    
    # Calculate Pass
    # Threshold: 60 points (e.g., Added both new people + retained most old ones)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "attendees_found": current_attendees,
            "event_id_match": baseline_id == final_id
        }
    }