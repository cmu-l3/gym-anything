#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_cancel_missed_flights(traj, env_info, task_info):
    """
    Verifies that missed flights were cancelled while valid ones were preserved.
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
    feedback = []
    
    records = result.get("records", {})
    
    # CONSTANTS (Assumed from typical Django choices, adjust if Aerobridge differs)
    # Usually: 1=Planned, 2=Active, 3=Completed, 4=Cancelled
    # We look for the status to NOT be 1 (Planned) and ideally be 4 (Cancelled) for ghosts
    STATUS_PLANNED = 1
    STATUS_CANCELLED = 4
    STATUS_COMPLETED = 3

    # Check 1: Ghost Flight 1 (Old, Planned) -> Should be Cancelled
    ghost_1 = records.get("ghost_1")
    if ghost_1 and ghost_1 != "MISSING":
        if ghost_1["status"] == STATUS_CANCELLED:
            score += 25
            feedback.append("✓ Old ghost flight correctly cancelled.")
        elif ghost_1["status"] != STATUS_PLANNED:
            score += 15
            feedback.append("✓ Old ghost flight status changed (but not strictly to Cancelled ID).")
        else:
            feedback.append("✗ Old ghost flight still in 'Planned' status.")
    else:
        feedback.append("⚠ Could not find Ghost Flight 1 record.")

    # Check 2: Ghost Flight Recent (Recent past, Planned) -> Should be Cancelled
    ghost_recent = records.get("ghost_recent")
    if ghost_recent and ghost_recent != "MISSING":
        if ghost_recent["status"] == STATUS_CANCELLED:
            score += 25
            feedback.append("✓ Recent ghost flight correctly cancelled.")
        elif ghost_recent["status"] != STATUS_PLANNED:
            score += 15
            feedback.append("✓ Recent ghost flight status changed.")
        else:
            feedback.append("✗ Recent ghost flight still in 'Planned' status.")
    else:
        feedback.append("⚠ Could not find Recent Ghost Flight record.")

    # Check 3: Completed Flight (Old, Completed) -> Should NOT change
    completed = records.get("completed")
    if completed and completed != "MISSING":
        if completed["status"] == STATUS_COMPLETED:
            score += 20
            feedback.append("✓ Historical completed flight preserved.")
        else:
            feedback.append(f"✗ Historical completed flight was modified! (Status: {completed['status']})")
    
    # Check 4: Future Flight (Future, Planned) -> Should NOT change
    future = records.get("future")
    if future and future != "MISSING":
        if future["status"] == STATUS_PLANNED:
            score += 20
            feedback.append("✓ Future planned flight preserved.")
        else:
            feedback.append(f"✗ Future flight was incorrectly cancelled/modified! (Status: {future['status']})")

    # Check 5: Log File Creation
    if result.get("log_exists"):
        score += 5
        feedback.append("✓ Log file created.")
        content = result.get("log_content", "")
        # Check if the cancelled IDs are in the log
        if ghost_1 and str(ghost_1["id"]) in content:
            score += 5
            feedback.append("✓ Log contains correct cancelled flight IDs.")
    else:
        feedback.append("✗ Log file not found.")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }