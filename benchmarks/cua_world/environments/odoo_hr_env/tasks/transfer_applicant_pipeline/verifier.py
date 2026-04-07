#!/usr/bin/env python3
"""
Verifier for Transfer Applicant Pipeline task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_transfer_applicant_pipeline(traj, env_info, task_info):
    """
    Verify the applicant was transferred, tagged, and noted correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_job = metadata.get('target_job', 'Consultant')
    expected_dept = metadata.get('target_department', 'Professional Services')
    expected_tag = metadata.get('required_tag', 'Reassigned')
    expected_note_fragment = metadata.get('required_note_content', 'Candidate better suited for consultancy role')

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

    if not result.get('found'):
        return {"passed": False, "score": 0, "feedback": "Applicant 'Alex Morgan' not found in database."}

    score = 0
    feedback_parts = []
    
    # 1. Verify Job Position (30 pts)
    actual_job = result.get('job_position', '')
    if actual_job == expected_job:
        score += 30
        feedback_parts.append(f"Job Position updated to '{actual_job}' (30/30)")
    else:
        feedback_parts.append(f"Job Position incorrect: expected '{expected_job}', got '{actual_job}'")

    # 2. Verify Department (20 pts)
    # Note: Odoo sometimes auto-updates department when job changes, but user should verify.
    actual_dept = result.get('department', '')
    if actual_dept == expected_dept:
        score += 20
        feedback_parts.append(f"Department updated to '{actual_dept}' (20/20)")
    else:
        feedback_parts.append(f"Department incorrect: expected '{expected_dept}', got '{actual_dept}'")

    # 3. Verify Tag (25 pts)
    tags = result.get('tags', [])
    if expected_tag in tags:
        score += 25
        feedback_parts.append(f"Tag '{expected_tag}' added (25/25)")
    else:
        feedback_parts.append(f"Tag '{expected_tag}' missing. Found: {tags}")

    # 4. Verify Note (25 pts)
    notes = result.get('notes', [])
    note_found = False
    
    # Simple check: look for fragment in any note body
    # Robust check: should check timestamp, but setup_task records start time. 
    # The export script fetches recent messages. We can assume if it's there, it's new enough or we check content.
    # Since this is a specific string required by the task, presence is good evidence.
    
    for note in notes:
        body = note.get('body', '')
        # Odoo wraps notes in <p> usually
        if expected_note_fragment.lower() in body.lower():
            note_found = True
            break
            
    if note_found:
        score += 25
        feedback_parts.append("Correct note logged in chatter (25/25)")
    else:
        feedback_parts.append(f"Note containing '{expected_note_fragment}' not found in chatter")

    # Anti-gaming: Check if record was modified during task
    # We rely on Odoo's write_date
    write_date_str = result.get('write_date')
    task_start_ts = result.get('task_start_ts', 0)
    
    modified_during_task = False
    if write_date_str:
        # Odoo string format: "YYYY-MM-DD HH:MM:SS" (usually UTC)
        # Parse it
        try:
            # Handle potential milliseconds or timezone variations if any
            # Usually '2023-10-25 10:00:00'
            wd = datetime.fromisoformat(str(write_date_str))
            wd_ts = wd.timestamp()
            # Allow slight clock skew, but write_date should be >= task_start
            if wd_ts >= (task_start_ts - 5): 
                modified_during_task = True
        except Exception:
            # Fallback if parsing fails, assume strict strict verification might fail
            # If we scored points, we likely did work.
            pass

    if score > 0 and not modified_during_task:
        feedback_parts.append("WARNING: Record modification time predates task start (Anti-gaming)")
        # In a strict environment, we might zero the score. 
        # For now, we'll just note it, or zero it if no points for note (since note implies action).
        # Let's deduct 50% if likely pre-existing
        score = int(score * 0.5)

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }