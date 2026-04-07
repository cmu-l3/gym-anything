#!/usr/bin/env python3
"""
Verifier for add_patient_chart_note task.

Uses a multi-signal approach:
1. Programmatic database verification (text must exist in DB and MUST NOT have existed before task)
2. VLM Trajectory Verification (proves the agent navigated through the UI to the correct patient)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_vlm_prompt():
    """Build the VLM prompt for trajectory verification."""
    return """Examine this sequence of screenshots from a user interacting with the FreeMED Electronic Medical Record system.

Please verify the following actions:
1. Did the user search for and open the patient chart for a patient named "David Chen"?
2. Did the user navigate to a Notes, Annotations, or Alerts section within the patient's chart?
3. Is there evidence of the user entering text about an ASL interpreter into a text box/form?
4. Did the user attempt to save or submit this note?

Respond strictly in JSON format with the following keys:
{
    "opened_david_chen_chart": true/false,
    "navigated_to_notes": true/false,
    "entered_text": true/false,
    "saved_note": true/false,
    "observations": "Brief summary of what you see in the screenshots regarding these steps"
}"""

def verify_add_patient_chart_note(traj, env_info, task_info):
    """
    Verify that the chart note was successfully added to David Chen's record.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy the exported result JSON from the container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    pre_count = result.get('pre_task_string_count', 0)
    post_count = result.get('post_task_string_count', 0)
    note_exists = result.get('note_table_record_exists', False)
    
    # ---------------------------------------------------------
    # Programmatic DB Verification (40 points)
    # ---------------------------------------------------------
    string_newly_added = (post_count > 0) and (post_count > pre_count)
    
    if string_newly_added:
        score += 30
        feedback_parts.append("Target text successfully saved to the database.")
    elif post_count > 0 and pre_count > 0:
        # Anti-gaming: string was already there. Did they add a second one?
        if post_count > pre_count:
            score += 30
            feedback_parts.append("Additional instance of target text saved to database.")
        else:
            feedback_parts.append("Target text found in database, but was present BEFORE task (Anti-gaming check failed).")
    else:
        feedback_parts.append("Target text NOT found in the database.")
        
    if note_exists:
        score += 10
        feedback_parts.append(f"Structured note record found (Subject: {result.get('note_subject', 'Unknown')}).")
        
    # ---------------------------------------------------------
    # VLM Trajectory Verification (60 points)
    # ---------------------------------------------------------
    vlm_feedback = "VLM check skipped or failed."
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            # Combine sampled frames and final screenshot
            vlm_images = frames + [final] if final else frames
            
            if vlm_images:
                vlm_result = query_vlm(
                    prompt=build_vlm_prompt(),
                    images=vlm_images
                )
                
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    
                    if parsed.get("opened_david_chen_chart"):
                        score += 20
                        feedback_parts.append("VLM confirms chart for David Chen was opened.")
                    else:
                        feedback_parts.append("VLM did not detect navigation to David Chen's chart.")
                        
                    if parsed.get("navigated_to_notes") or parsed.get("entered_text"):
                        score += 25
                        feedback_parts.append("VLM confirms text entry in the notes/annotations interface.")
                        
                    if parsed.get("saved_note"):
                        score += 15
                        feedback_parts.append("VLM confirms note save action.")
                        
                    vlm_feedback = parsed.get("observations", "No observations provided.")
            else:
                feedback_parts.append("No screenshots available for VLM verification.")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback_parts.append(f"VLM verification error: {e}")

    # Determine final pass status
    # Must have actually added the text to the DB AND shown UI interaction
    key_criteria_met = string_newly_added and score >= 65
    passed = key_criteria_met

    feedback_parts.append(f"VLM Observations: {vlm_feedback}")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }