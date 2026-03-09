#!/usr/bin/env python3
"""
Verifier for log_corporate_events task.

Verifies:
1. Portfolio file persistence (modified timestamp).
2. XML content: Existence of an event on 2024-10-10 for Tesla.
3. XML content: Label content matches "Cybercab" or related keywords.
4. VLM: Optional check if programmatic verification is ambiguous.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_log_corporate_events(traj, env_info, task_info):
    """
    Verify that the agent added the specific corporate event note.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment interface error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_date = metadata.get('expected_date', '2024-10-10')
    expected_keywords = metadata.get('expected_keywords', ['Cybercab', 'Robot'])
    
    # 1. Load programmatic results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Saved (10 pts) ---
    if result.get('file_modified'):
        score += 10
        feedback_parts.append("Portfolio file saved.")
    else:
        feedback_parts.append("Portfolio file NOT saved (timestamps unchanged).")

    # --- Criterion 2: Security Found (10 pts) ---
    if result.get('security_found'):
        score += 10
    else:
        feedback_parts.append("Target security (Tesla) not found in file.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # --- Criterion 3: Event Created (40 pts) ---
    events = result.get('events_data', [])
    if not events:
        feedback_parts.append("No events found for Tesla.")
        
        # FALLBACK: VLM check if programmatic check failed (maybe UI didn't save to XML yet?)
        # This is a safety net.
        if query_vlm:
            frames = sample_trajectory_frames(traj, 5)
            final_scr = get_final_screenshot(traj)
            prompt = "Does the screen show a dialog or form for adding an 'Event' or 'Note' to a stock chart? Is '2024-10-10' or 'Cybercab' visible?"
            vlm_resp = query_vlm(images=frames + [final_scr], prompt=prompt)
            if vlm_resp.get('success') and "yes" in vlm_resp.get('result', '').lower():
                score += 10
                feedback_parts.append("(VLM) UI shows event entry attempt, but file not saved/updated.")
        
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}
    else:
        score += 40
        feedback_parts.append("Event entry found in XML.")

    # --- Criterion 4: Data Accuracy (40 pts) ---
    date_match = False
    label_match = False
    
    for evt in events:
        # Check Date
        if expected_date in evt.get('date', ''):
            date_match = True
        
        # Check Label
        label_text = evt.get('label', '').lower()
        if any(k.lower() in label_text for k in expected_keywords):
            label_match = True
    
    if date_match:
        score += 20
        feedback_parts.append(f"Correct date: {expected_date}.")
    else:
        feedback_parts.append(f"Incorrect date (found {events[0].get('date')}).")

    if label_match:
        score += 20
        feedback_parts.append("Correct label keywords found.")
    else:
        feedback_parts.append(f"Label mismatch (found '{events[0].get('label')}').")

    # Final Pass/Fail Check
    # Must have saved file, created event, and got at least date OR label right
    passed = (result.get('file_modified') and 
              len(events) > 0 and 
              (date_match or label_match))

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }