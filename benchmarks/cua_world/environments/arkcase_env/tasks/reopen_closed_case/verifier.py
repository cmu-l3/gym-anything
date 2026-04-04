#!/usr/bin/env python3
"""
Verifier for reopen_closed_case task.
Checks:
1. Anti-gaming: Task duration > 15 seconds.
2. Status Check: Case status changed from CLOSED to ACTIVE/OPEN.
3. Content Check: Reopening note added with required keywords.
4. Visual Check: VLM verification of trajectory/final state.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reopen_case(traj, env_info, task_info):
    """
    Verify that the case was reopened and the note was added.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_keywords = metadata.get('required_note_keywords', [])
    forbidden_status = metadata.get('forbidden_status', 'CLOSED')

    # Load result from container
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
    
    # 1. Anti-Gaming Check (15 pts)
    start_time = result.get('task_start', 0)
    end_time = result.get('task_end', 0)
    duration = end_time - start_time
    
    if duration >= 15:
        score += 15
        feedback_parts.append("Duration check passed")
    else:
        feedback_parts.append(f"Task completed too quickly ({duration}s) - suspicious")

    # 2. Status Check (35 pts)
    final_status = result.get('final_status', 'UNKNOWN').upper()
    if final_status != forbidden_status and final_status != 'UNKNOWN' and final_status != "":
        score += 35
        feedback_parts.append(f"Status changed to {final_status}")
    else:
        feedback_parts.append(f"Status remains {final_status} (Expected active status)")

    # 3. Note Content Check (35 pts)
    initial_note_count = result.get('initial_note_count', 0)
    final_notes = result.get('final_notes', [])
    final_note_count = len(final_notes)
    
    note_found = False
    keyword_matches = 0
    
    # Only check notes if count increased
    if final_note_count > initial_note_count:
        # Check the most recent notes
        # We look for the note containing our specific text
        for note in final_notes:
            # Handle different note structures from API
            note_text = note.get('note', note.get('noteText', note.get('content', str(note))))
            if not isinstance(note_text, str):
                note_text = str(note_text)
            note_text = note_text.lower()
            
            # Count keywords
            current_matches = sum(1 for kw in required_keywords if kw.lower() in note_text)
            
            if current_matches >= 3: # Threshold to identify THIS is the reopening note
                note_found = True
                keyword_matches = current_matches
                break
    
    if note_found:
        if keyword_matches >= len(required_keywords):
            score += 35
            feedback_parts.append("Perfect reopening note found")
        else:
            score += 25
            feedback_parts.append(f"Reopening note found but partial match ({keyword_matches}/{len(required_keywords)} keywords)")
    elif final_note_count > initial_note_count:
        score += 10
        feedback_parts.append("New note added but content incorrect")
    else:
        feedback_parts.append("No new notes added")

    # 4. VLM Verification (15 pts)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        # We verify that they actually interacted with the case UI
        prompt = """
        Review these screenshots of an ArkCase task.
        The user should have:
        1. Opened a case titled "Public Records Request - Historical Budget Data"
        2. Changed status from Closed to Active
        3. Added a note
        
        Do you see evidence of:
        - The specific case details page?
        - A status dropdown/button being clicked?
        - A "Add Note" dialog or text input?
        
        Answer YES or NO and provide a confidence score (0-10).
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final_img], prompt=prompt)
            if vlm_resp.get("success"):
                content = vlm_resp.get("parsed", {}).get("answer", "").lower()
                # Basic check - if VLM thinks it happened, give points
                # This is a soft check to back up the API checks
                if "yes" in content or "evidence" in vlm_resp.get("result", "").lower():
                    vlm_score = 15
                    feedback_parts.append("Visual evidence confirmed")
                else:
                    feedback_parts.append("Visual evidence unclear")
            else:
                 feedback_parts.append("VLM query failed")
        except:
             feedback_parts.append("VLM error")
    else:
        # Fallback if VLM not available but other checks passed
        if score >= 50: 
            vlm_score = 15
            feedback_parts.append("VLM skipped (implicit pass)")
            
    score += vlm_score

    # Final Calculation
    passed = score >= 70 and (final_status != forbidden_status) and note_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }