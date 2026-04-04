#!/usr/bin/env python3
"""
Verifier for delete_visitor_record task.

Verification Strategy:
1. Primary: VLM verification of the final state (list view) and trajectory (delete action).
2. Secondary: Database file modification timestamp check.
3. Tertiary: String check in DB file (backup signal).

Why VLM is primary?
- MS Access/SQL CE databases used by Lobby Track often perform "soft deletes" or don't 
  compact immediately, meaning `strings` might still find the deleted name.
- The visual state of the visitor list is the source of truth for the user.
"""

import json
import tempfile
import os
import logging
import sys
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_visitor_record(traj, env_info, task_info):
    """
    Verify that the 'John Testentry' record was deleted.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
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
    feedback_parts = []
    
    # 2. Check Database Modification (Anti-Gaming)
    # The DB file MUST be modified if a record was deleted.
    db_modified = result.get('db_modified', False)
    db_exists = result.get('db_exists', False)
    
    if not db_exists:
        feedback_parts.append("CRITICAL: Database file not found.")
    elif db_modified:
        score += 20
        feedback_parts.append("Database file modified successfully.")
    else:
        feedback_parts.append("Warning: Database file timestamp did not change (Action might not be saved).")

    # 3. Check DB Content (Heuristic)
    # If 'Testentry' is gone from strings, that's a strong pass.
    # If present, it might be a soft delete, so we don't penalize heavily if VLM says pass.
    content_sample = result.get('db_content_sample', "")
    testentry_present = "Testentry" in content_sample
    others_present = all(name in content_sample for name in ["Gonzalez", "Chen", "Williams"])
    
    if not testentry_present:
        score += 30
        feedback_parts.append("Deleted record not found in DB file (Strong Pass).")
    else:
        feedback_parts.append("Record text still found in DB file (could be soft delete) - relying on visual check.")

    if others_present:
        score += 10
        feedback_parts.append("Other records preserved in DB file.")
    else:
        # If others are missing, agent might have deleted wrong file or corrupted DB
        feedback_parts.append("Warning: Some expected records missing from DB file string dump.")

    # 4. VLM Verification (The Decider)
    # We check:
    # A. Final screen shows visitor list WITHOUT John Testentry
    # B. Trajectory shows interaction with Delete/Remove button or menu
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if not final_screen:
         return {"passed": False, "score": score, "feedback": "No screenshots available"}

    # VLM Prompt
    prompt = """
    You are verifying a task in 'Jolly Lobby Track' visitor management software.
    The goal was to DELETE the visitor 'John Testentry' but KEEP 'Maria Gonzalez', 'David Chen', and 'Sarah Williams'.
    
    Review the screenshots (sequence leading to final state):
    1. Do you see the visitor 'John Testentry' in the FINAL screenshot's list? (Should be GONE)
    2. Do you see the other visitors (Gonzalez, Chen, Williams) in the final list? (Should be PRESENT)
    3. In the previous frames, did the user perform a delete action (click Delete button, right-click Remove, confirm dialog)?
    
    Respond in JSON:
    {
        "john_gone_final": true/false,
        "others_present_final": true/false,
        "delete_action_observed": true/false,
        "reasoning": "..."
    }
    """
    
    vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
    
    if vlm_res.get('success'):
        parsed = vlm_res.get('parsed', {})
        john_gone = parsed.get('john_gone_final', False)
        others_present = parsed.get('others_present_final', False)
        action_observed = parsed.get('delete_action_observed', False)
        
        if john_gone:
            score += 30
            feedback_parts.append("Visual: 'John Testentry' is gone from final list.")
        else:
            feedback_parts.append("Visual: 'John Testentry' still visible in list.")
            
        if others_present:
            score += 10
            feedback_parts.append("Visual: Other visitors still visible.")
            
        if action_observed:
            score += 10 # Extra confidence
            feedback_parts.append("Visual: Delete action observed in workflow.")
    else:
        feedback_parts.append("VLM verification failed to run.")

    # Final Scoring Logic
    # Pass if:
    # 1. John is visually gone OR textually gone from DB
    # 2. DB was modified (proof of action)
    # 3. Score >= 70
    
    primary_success = (not testentry_present) or (vlm_res.get('success') and vlm_res.get('parsed', {}).get('john_gone_final'))
    
    passed = primary_success and db_modified and score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }