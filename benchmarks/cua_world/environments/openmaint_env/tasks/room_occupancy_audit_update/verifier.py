#!/usr/bin/env python3
"""
Verifier for room_occupancy_audit_update task.

Scoring:
- RM-A-101 (Office+User -> Occupied): 20 pts
- RM-A-102 (Office+NoUser -> Vacant): 20 pts
- RM-A-103 (Meeting -> Common): 20 pts
- RM-A-104 (Storage+User -> Common): 25 pts (Trick question)
- RM-A-105 (Office+User -> Occupied): 15 pts (Preservation)

Pass Threshold: 60/100
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_room_occupancy_audit_update(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    rooms = result.get("rooms", {})
    if not rooms:
        return {"passed": False, "score": 0, "feedback": "No room data found"}

    score = 0
    feedback_parts = []
    
    # 1. RM-A-101: Office with User -> Occupied (20 pts)
    r101 = rooms.get("RM-A-101", {})
    if r101.get("is_correct"):
        score += 20
        feedback_parts.append("RM-A-101 Correct (Occupied)")
    else:
        feedback_parts.append(f"RM-A-101 Incorrect (Expected Occupied, got '{r101.get('current_notes')}')")

    # 2. RM-A-102: Office no User -> Vacant (20 pts)
    r102 = rooms.get("RM-A-102", {})
    if r102.get("is_correct"):
        score += 20
        feedback_parts.append("RM-A-102 Correct (Vacant)")
    else:
        feedback_parts.append(f"RM-A-102 Incorrect (Expected Vacant, got '{r102.get('current_notes')}')")

    # 3. RM-A-103: Meeting Room -> Common Area (20 pts)
    r103 = rooms.get("RM-A-103", {})
    if r103.get("is_correct"):
        score += 20
        feedback_parts.append("RM-A-103 Correct (Common Area)")
    else:
        feedback_parts.append(f"RM-A-103 Incorrect (Expected Common Area, got '{r103.get('current_notes')}')")

    # 4. RM-A-104: Storage with User -> Common Area (25 pts)
    # This checks if they followed the rule "Non-office is always Common Area"
    r104 = rooms.get("RM-A-104", {})
    if r104.get("is_correct"):
        score += 25
        feedback_parts.append("RM-A-104 Correct (Common Area - Rule Applied)")
    elif r104.get("current_notes", "").lower() == "occupied":
        feedback_parts.append("RM-A-104 Failed (Marked as Occupied despite being Storage)")
    else:
        feedback_parts.append(f"RM-A-104 Incorrect (Expected Common Area, got '{r104.get('current_notes')}')")

    # 5. RM-A-105: Preservation (15 pts)
    r105 = rooms.get("RM-A-105", {})
    if r105.get("is_correct"):
        score += 15
        feedback_parts.append("RM-A-105 Preserved")
    else:
        feedback_parts.append("RM-A-105 Wrongly modified")

    # Anti-gaming: Do Nothing Check
    # If NO rooms changed from initial state, score should be 0
    any_changed = any(r.get("changed") for r in rooms.values())
    if not any_changed:
        score = 0
        feedback_parts = ["DO NOTHING DETECTED: No changes made to any records."]

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }