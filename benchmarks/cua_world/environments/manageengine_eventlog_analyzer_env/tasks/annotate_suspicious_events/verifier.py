#!/usr/bin/env python3
"""
Verifier for annotate_suspicious_events task.

Verification Strategy:
1. Primary: Database check. The string "CASE-999" must exist in the EventLog Analyzer database.
   This confirms the agent successfully added and saved the note.
2. Secondary: VLM Trajectory check. Verify the agent actually used the Search/Event interface.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_annotate_suspicious_events(traj, env_info, task_info):
    """
    Verify that the agent searched for logs and added the correct note.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Database Verification (60 points)
    # The ultimate proof is data persistence.
    note_found = result.get("note_found_in_db", False)
    
    if note_found:
        score += 60
        feedback_parts.append("Success: Note 'CASE-999' found in database.")
    else:
        feedback_parts.append("Failure: Note 'CASE-999' NOT found in database.")

    # 2. VLM Trajectory Verification (40 points)
    # Ensure they didn't just run a SQL INSERT command via terminal (anti-gaming),
    # but actually used the UI.
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying a user action in ManageEngine EventLog Analyzer.
    The user was supposed to:
    1. Search for log events.
    2. Click on a specific event.
    3. Add a "Note" or "Annotation" to that event.
    
    Look at these screenshots.
    - Do you see the EventLog Analyzer interface?
    - Do you see a Search bar or Search results?
    - Do you see any popup dialog for "Add Note", "Annotate", or entering text?
    - Do you see the text "CASE-999" being typed or displayed?
    
    Answer strictly in JSON:
    {
        "ui_visible": boolean,
        "search_seen": boolean,
        "note_dialog_seen": boolean,
        "case_id_seen": boolean,
        "confidence": float (0-1)
    }
    """
    
    try:
        vlm_response = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
        vlm_data = vlm_response.get('parsed', {})
        
        vlm_score = 0
        if vlm_data.get('ui_visible'):
            vlm_score += 10
        if vlm_data.get('search_seen'):
            vlm_score += 10
        if vlm_data.get('note_dialog_seen'):
            vlm_score += 10
        if vlm_data.get('case_id_seen'):
            vlm_score += 10
            
        score += vlm_score
        feedback_parts.append(f"VLM Analysis: UI interactions verified ({vlm_score}/40 pts).")
        
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if DB check passed, give partial VLM credit to avoid false fail on VLM error
        if note_found:
            score += 20
            feedback_parts.append("VLM check failed, but DB confirmed success.")

    # 3. Final Assessment
    passed = (note_found is True) and (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }