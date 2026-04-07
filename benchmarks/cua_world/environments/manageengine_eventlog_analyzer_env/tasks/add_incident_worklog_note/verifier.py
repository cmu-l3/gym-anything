#!/usr/bin/env python3
import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_incident_worklog_note(traj, env_info, task_info):
    """
    Verify that the agent added the correct worklog note to the specific alert.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values
    metadata = task_info.get('metadata', {})
    target_text = metadata.get('target_note_text', "Initial triage complete. Escalating to L2.")
    target_alert_msg = metadata.get('target_alert_message', "CORE_DUMP_DETECTED_001")

    # Load result from container
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
    
    # Check 1: Alert Generation (Prerequisite)
    # The setup script should have created this, but we verify it exists to ensure fairness
    db_alert_record = result.get('db_alert_record', '')
    if target_alert_msg in db_alert_record:
        score += 10
        feedback.append("Target alert found in system.")
    else:
        feedback.append("Warning: Target alert 'CORE_DUMP_DETECTED_001' not found in DB check (Task setup issue?).")
        # If the alert isn't there, the agent couldn't have annotated it.
        # However, sometimes DB dump format varies. If the note is found, we assume alert existed.

    # Check 2: Note Existence and Content
    db_note_record = result.get('db_note_record', '')
    
    # Normalize for comparison (ignore whitespace/case issues if minor)
    note_found = False
    
    # We look for the key phrase
    key_phrase_1 = "Initial triage complete"
    key_phrase_2 = "Escalating to L2"
    
    if key_phrase_1.lower() in db_note_record.lower() and key_phrase_2.lower() in db_note_record.lower():
        note_found = True
        score += 90  # Major points for doing the work
        feedback.append("Worklog note successfully added with correct text.")
    elif key_phrase_1.lower() in db_note_record.lower():
        note_found = True
        score += 50
        feedback.append("Worklog note found but incomplete (missing 'Escalating to L2').")
    else:
        feedback.append("No matching worklog note found in database.")

    # Pass criteria
    passed = (score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }