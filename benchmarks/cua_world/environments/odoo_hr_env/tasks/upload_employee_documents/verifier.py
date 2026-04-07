#!/usr/bin/env python3
"""
Verifier for upload_employee_documents task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_upload_documents(traj, env_info, task_info):
    """
    Verifies that the agent uploaded the correct documents to Eli Lambert's chatter.
    """
    # 1. Setup copy from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: Copy function not available"}

    # 2. Load result data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Check criteria
    score = 0
    feedback = []
    
    # Metadata targets
    target_note = task_info['metadata']['note_content']
    target_file_1 = "eli_lambert_id.jpg"
    target_file_2 = "eli_lambert_contract.pdf"

    if not result.get("employee_found"):
        return {"passed": False, "score": 0, "feedback": "Could not find employee 'Eli Lambert' in database."}
    
    # Analyze found notes
    notes = result.get("notes_found", [])
    
    # Find the best matching note
    best_note = None
    note_score = 0
    
    for note in notes:
        current_score = 0
        body = note.get('body', '')
        
        # Check text content (partial match because Odoo wraps in <p> tags)
        if target_note in body:
            current_score += 20
        
        # Check attachments
        att_names = [a['name'] for a in note.get('attachments', [])]
        if target_file_1 in att_names:
            current_score += 30
        if target_file_2 in att_names:
            current_score += 30
        
        # Check if internal (bonus/secondary check)
        # In Odoo 17, 'Log Note' sets is_internal=True or message_type='comment' distinguishably
        # We give points if the note exists and has content
        if target_note in body:
            current_score += 10 # Is a valid note
            
        if current_score > note_score:
            note_score = current_score
            best_note = note

    # Compile final score
    if best_note:
        score = note_score
        
        # Generate detailed feedback
        body = best_note.get('body', '')
        att_names = [a['name'] for a in best_note.get('attachments', [])]
        
        if target_note in body:
            feedback.append("Correct note content found.")
        else:
            feedback.append(f"Note content mismatch. Expected '{target_note}'.")
            
        if target_file_1 in att_names:
            feedback.append(f"Attachment '{target_file_1}' found.")
        else:
            feedback.append(f"Missing attachment '{target_file_1}'.")
            
        if target_file_2 in att_names:
            feedback.append(f"Attachment '{target_file_2}' found.")
        else:
            feedback.append(f"Missing attachment '{target_file_2}'.")
            
        # Employee Check (implicit in how we searched)
        score += 10 # Points for finding the correct employee to attach to
        feedback.append("Attached to correct employee 'Eli Lambert'.")

    else:
        feedback.append("No matching note found on Eli Lambert's profile.")

    # Threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }