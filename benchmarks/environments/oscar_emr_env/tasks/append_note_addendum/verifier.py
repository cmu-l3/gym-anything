#!/usr/bin/env python3
"""
Verifier for append_note_addendum task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_append_note_addendum(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    original_text_fragment = "Subjective: c/o epigastric pain"
    addendum_text_fragment = "avoid spicy foods"
    
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

    notes = result.get('notes', [])
    initial_note_id = result.get('initial_note_id')
    
    # Scoring
    score = 0
    feedback = []
    
    # Find the relevant note
    # Ideally, the agent updated the initial note.
    # Sometimes Oscar might create a linked note or revision, but for this task 
    # and typical usage, the note field is updated.
    
    target_note = None
    
    # Check if original note was updated
    for note in notes:
        if str(note.get('note_id')) == str(initial_note_id):
            target_note = note
            break
            
    # If not found (maybe deleted?), check other notes
    if not target_note and notes:
        target_note = notes[-1] # Take the most recent one
        feedback.append("Warning: Initial note ID not found, checking most recent note.")

    if not target_note:
        return {"passed": False, "score": 0, "feedback": "No clinical notes found for patient today."}

    content = target_note.get('note_content', '')
    signed = str(target_note.get('signed', '0'))
    
    # Criteria 1: Original text preserved (30 pts)
    if original_text_fragment.lower() in content.lower():
        score += 30
        feedback.append("Original text preserved.")
    else:
        feedback.append("Failed: Original text missing from note.")

    # Criteria 2: Addendum added (40 pts)
    if addendum_text_fragment.lower() in content.lower():
        score += 40
        feedback.append("Addendum text found.")
    else:
        feedback.append("Failed: Addendum text not found.")

    # Criteria 3: Note is signed (10 pts)
    if signed == '1':
        score += 10
        feedback.append("Note is signed.")
    else:
        feedback.append("Note is NOT signed.")

    # Criteria 4: Target correctness (20 pts)
    # If we found the specific ID we started with, full points.
    if str(target_note.get('note_id')) == str(initial_note_id):
        score += 20
        feedback.append("Correct note ID updated.")
    elif score > 0:
        # Partial credit if they made a NEW note instead of appending
        score += 10
        feedback.append("Created new note instead of appending to existing (partial credit).")

    passed = (score >= 70) and (original_text_fragment.lower() in content.lower()) and (addendum_text_fragment.lower() in content.lower())

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }