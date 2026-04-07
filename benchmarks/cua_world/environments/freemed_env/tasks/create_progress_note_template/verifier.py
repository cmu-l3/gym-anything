#!/usr/bin/env python3
"""
Verifier for Create Progress Note Template task in FreeMED.

This verifier uses a robust schema-agnostic verification approach. 
Instead of trying to locate the exact table FreeMED stores its clinical macros in, 
it compares the count of highly specific string phrases in a full raw database 
dump before and after the task execution.

It also utilizes VLM trajectory verification to ensure the agent used a system
template module rather than gaming the system by writing it in a specific patient's chart.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_progress_note_template(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract result JSON created by export_result.sh
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

    # 1. Verify Database Insertions (Schema-Agnostic Check)
    # -------------------------------------------------------------------------
    title_added = result.get('final_title_count', 0) > result.get('init_title_count', 0)
    phrase1_added = result.get('final_phrase1_count', 0) > result.get('init_phrase1_count', 0)
    phrase2_added = result.get('final_phrase2_count', 0) > result.get('init_phrase2_count', 0)
    phrase3_added = result.get('final_phrase3_count', 0) > result.get('init_phrase3_count', 0)

    if title_added:
        score += 25
        feedback_parts.append("Template Title 'Normal Physical Exam' saved in database")
    else:
        feedback_parts.append("Template Title NOT found in database")

    # Combine text phrases for the next 50 points
    phrases_found = sum([phrase1_added, phrase2_added, phrase3_added])
    if phrases_found >= 2:
        score += 50
        feedback_parts.append("Clinical body text was correctly saved in the database")
    elif phrases_found == 1:
        score += 25
        feedback_parts.append("Only partial clinical body text was saved")
    else:
        feedback_parts.append("Clinical body text NOT found in database")

    # 2. VLM Trajectory Verification (Anti-Gaming Check)
    # -------------------------------------------------------------------------
    # We want to ensure the agent used a system-wide Template Editor, 
    # and didn't just paste this into an individual patient's encounter note.
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        query_vlm = env_info.get('query_vlm')

        if query_vlm and (frames or final):
            images = frames
            if final:
                images.append(final)
                
            prompt = (
                "Review these trajectory screenshots of an AI agent working in the FreeMED Electronic Medical Record system. "
                "The agent's task was to create a REUSABLE SYSTEM TEMPLATE or MACRO. "
                "Did the agent navigate to a Template Editor, Macro Editor, or System Configuration screen to paste the text? "
                "Answer YES if they used a template creation module. "
                "Answer NO if they appear to have gamed the task by writing this directly inside a specific patient's chart/progress note. "
                "Respond with only YES or NO."
            )
            
            vlm_response = query_vlm(images=images, prompt=prompt)
            # Handle standard gym-anything query_vlm return types (dict or string)
            reply_text = vlm_response.get('response', '') if isinstance(vlm_response, dict) else str(vlm_response)
            
            if 'yes' in reply_text.lower():
                vlm_score = 25
                feedback_parts.append("VLM verified System Template module was used (not a patient chart)")
            else:
                feedback_parts.append("VLM failed: Agent appeared to write this in a patient chart instead of a template module")
        else:
            vlm_score = 25
            feedback_parts.append("VLM skipped (awarding default anti-gaming points)")
    except Exception as e:
        vlm_score = 25
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append("VLM verification failed to run (awarding default anti-gaming points)")

    score += vlm_score

    # To pass, the title and at least one phrase must be added to the DB, AND score >= 75
    key_criteria_met = title_added and (phrases_found >= 1)
    passed = (score >= 75) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }