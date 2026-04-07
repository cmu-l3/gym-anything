#!/usr/bin/env python3
"""
Verifier for send_internal_message task.

Criteria:
1. Message text found anywhere in the database (30 pts)
2. Message found in a messaging table, NOT a clinical note table (30 pts)
3. Subject line is included in the stored message (20 pts)
4. Trajectory frames show the agent interacting with the messaging module (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """Examine these sequential screenshots from an agent interacting with a medical records system.
    
Task: Verify if the agent used the system's Internal Messaging / Inbox module to send a message.

Look for the following indicators:
1. Did the agent open a 'Messages', 'Inbox', or 'Mail' interface? (Usually separate from a patient chart).
2. Did they compose a message addressed to 'smitchell' or 'Sarah Mitchell'?
3. Is there evidence they successfully hit send or save on the message form?

CRITICAL: If the agent is just typing a 'Progress Note' or 'Clinical Note' inside Maria Santos's patient chart, they did NOT use the internal messaging module.

Respond with a JSON object containing:
{
    "used_messaging_module": true/false,
    "addressed_to_correct_recipient": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what is visible in the frames"
}
"""

def verify_send_message(traj, env_info, task_info):
    """Verify that an internal message was successfully sent."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely retrieve results JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading results from environment: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    found_anywhere = result_data.get("found_anywhere", False)
    found_in_messages = result_data.get("found_in_messages", False)
    found_in_pnotes = result_data.get("found_in_pnotes", False)
    message_rows = result_data.get("message_rows", [])
    recipient_id = result_data.get("recipient_id")
    
    # 1. Check if text was saved anywhere
    if found_anywhere:
        score += 30
        feedback_parts.append("Target text successfully saved in database")
    else:
        feedback_parts.append("Failed to find target text 'lipid panel is back' in database")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    # 2. Check proper module usage
    if found_in_messages:
        score += 30
        feedback_parts.append("Correct module used (saved in messages table)")
    elif found_in_pnotes:
        feedback_parts.append("Gaming attempt detected: Saved as a progress note instead of an internal message")
    else:
        feedback_parts.append("Saved in an unexpected table, not recognized as messaging")
        
    # 3. Check for Subject line and Recipient inside the database row
    subject_present = False
    recipient_present = False
    
    for row in message_rows:
        row_str = json.dumps(row).lower()
        if "lab results" in row_str:
            subject_present = True
        if str(recipient_id) in row_str or "smitchell" in row_str or "sarah" in row_str:
            recipient_present = True
            
    if subject_present:
        score += 20
        feedback_parts.append("Subject line 'Lab Results' found in record")
    else:
        feedback_parts.append("Missing expected subject line")
        
    # 4. VLM Verification of Trajectory
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        query_vlm = env_info.get('query_vlm')
        if query_vlm and images:
            vlm_response = query_vlm(prompt=build_vlm_prompt(), images=images)
            vlm_parsed = vlm_response.get("parsed", {})
            
            if vlm_parsed.get("used_messaging_module") and vlm_parsed.get("addressed_to_correct_recipient"):
                score += 20
                feedback_parts.append("VLM visually confirmed correct messaging workflow")
            else:
                feedback_parts.append(f"VLM verification failed: {vlm_parsed.get('reasoning', 'No reasoning provided')}")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Soft fallback if VLM fails but DB shows recipient info
        if recipient_present and found_in_messages:
            score += 20
            feedback_parts.append("VLM fallback: Database record contains expected recipient ID")

    # Combine pass threshold logic
    passed = score >= 60 and found_in_messages
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }