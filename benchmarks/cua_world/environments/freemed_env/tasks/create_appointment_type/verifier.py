#!/usr/bin/env python3
"""
Verifier for the create_appointment_type task in FreeMED.

Uses a combination of programmatic schema-agnostic database verification
and VLM-based trajectory verification to ensure the task was completed properly
through the user interface.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_appointment_type(traj, env_info, task_info):
    """
    Verify the creation of 'Telehealth Counseling' Appointment Type.
    
    Scoring:
    - 40 pts: "Telehealth Counseling" is found in the database dump (created during task)
    - 30 pts: The database row containing the new type also contains "45"
    - 15 pts: VLM verifies trajectory shows navigation to configuration module
    - 15 pts: VLM verifies trajectory shows form completion and save
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract result JSON from the environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    created_during_task = result.get('created_during_task', False)
    db_duration_match = result.get('db_duration_match', False)
    initial_count = result.get('initial_match_count', 0)
    final_count = result.get('final_match_count', 0)

    # 1. Programmatic Check: Was the record created? (40 points)
    if created_during_task:
        score += 40
        feedback_parts.append(f"Appointment type created (matches: {initial_count} -> {final_count})")
    else:
        feedback_parts.append("FAIL: 'Telehealth Counseling' not created in database")
        
    # 2. Programmatic Check: Is the duration correct? (30 points)
    if db_duration_match and created_during_task:
        score += 30
        feedback_parts.append("Duration '45' successfully associated with the record")
    elif created_during_task:
        feedback_parts.append("FAIL: Duration '45' not found in the created record")

    # 3. VLM Verification (30 points)
    # We use trajectory frames rather than just final screenshot to prevent SQL injection/gaming
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        all_frames = frames + [final_frame] if final_frame else frames

        if all_frames:
            query_vlm = env_info.get('query_vlm')
            if query_vlm:
                prompt = """
                Review these screenshots from a web-based Electronic Medical Record (FreeMED). 
                The agent's task was to add a new Appointment Type (or Schedule Type) named 'Telehealth Counseling' with a duration of 45 minutes.

                Did the agent:
                1. Navigate to the proper system configuration or scheduling module to manage appointment types?
                2. Enter 'Telehealth Counseling' and '45' into the form and save the result?

                Respond in JSON format:
                {
                    "ui_navigation_correct": true/false,
                    "form_completed": true/false,
                    "observations": "brief summary"
                }
                """
                vlm_res = query_vlm(images=all_frames, prompt=prompt)
                
                if vlm_res and vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    ui_correct = parsed.get('ui_navigation_correct', False)
                    form_completed = parsed.get('form_completed', False)

                    if ui_correct:
                        score += 15
                        feedback_parts.append("VLM: UI Navigation verified")
                    else:
                        feedback_parts.append("VLM: UI Navigation not observed")

                    if form_completed:
                        score += 15
                        feedback_parts.append("VLM: Form completion verified")
                    else:
                        feedback_parts.append("VLM: Form completion not observed")
                else:
                    feedback_parts.append("VLM check failed or returned invalid response")
            else:
                feedback_parts.append("VLM query function not available")
        else:
            feedback_parts.append("No trajectory frames found for VLM verification")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback_parts.append(f"VLM verification error: {e}")

    # Pass logic: Must have created the DB record (prevents bypass) and scored >= 70
    passed = (created_during_task and score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }