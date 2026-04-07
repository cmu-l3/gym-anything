#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_add_school_calendar_event(traj, env_info, task_info):
    """
    Verify the add_school_calendar_event task.
    
    Criteria:
    1. Database Record (60 pts): Event exists in DB with correct title and date.
    2. Details Correct (20 pts): Description matches keywords, not marked as holiday.
    3. Visual Verification (20 pts): VLM confirms calendar interaction.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "Annual Science Fair")
    expected_date = metadata.get('expected_date', "2026-05-20")
    
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

    score = 0
    feedback = []
    
    # 2. Database Verification
    event_found = result.get('event_found', False)
    event_data = result.get('event_data', {})
    
    actual_title = event_data.get('title', "")
    actual_date = event_data.get('date', "")
    actual_desc = event_data.get('description', "")
    is_holiday = event_data.get('is_holiday', False)

    if event_found:
        score += 30
        feedback.append("Event record found in database.")
        
        # Title Check
        if expected_title.lower() in actual_title.lower():
            score += 15
            feedback.append(f"Title correct: '{actual_title}'.")
        else:
            feedback.append(f"Title mismatch: Expected '{expected_title}', found '{actual_title}'.")

        # Date Check
        if expected_date in actual_date:
            score += 15
            feedback.append(f"Date correct: {actual_date}.")
        else:
            feedback.append(f"Date mismatch: Expected {expected_date}, found {actual_date}.")

        # Description Check (Keywords)
        keywords = metadata.get('expected_description_keywords', [])
        found_keywords = [k for k in keywords if k.lower() in actual_desc.lower()]
        if len(found_keywords) > 0:
            score += 10
            feedback.append("Description contains expected details.")
        else:
            feedback.append("Description missing expected details.")

        # Holiday Check (Should NOT be holiday)
        if not is_holiday:
            score += 10
            feedback.append("Correctly marked as Event (not Holiday).")
        else:
            feedback.append("Incorrectly marked as a Holiday.")
            
    else:
        feedback.append("No event found matching title or date in database.")

    # 3. VLM Verification (Visual Confirmation)
    # Check if the user actually navigated to the calendar and we can see it
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = (
        "You are verifying an agent's actions in the OpenSIS student information system. "
        "The agent was supposed to add a calendar event 'Annual Science Fair' on May 20, 2026. "
        "Review the screenshots."
        "1. Do you see the OpenSIS Calendar module or 'School Setup' menu?"
        "2. Do you see a form for adding an event or a calendar view showing 'Science Fair'?"
        "Respond with JSON: {\"calendar_visited\": true/false, \"event_visible\": true/false, \"reason\": \"...\"}"
    )
    
    vlm_result = query_vlm(
        images=frames + [final_screen],
        prompt=vlm_prompt
    )
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("calendar_visited", False):
            score += 10
            feedback.append("VLM: Calendar module access detected.")
        if parsed.get("event_visible", False):
            score += 10
            feedback.append("VLM: Event confirmed visible on screen.")
    else:
        feedback.append("VLM verification failed to process.")

    # Final Evaluation
    passed = (score >= 70) and event_found and (expected_date in actual_date)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }