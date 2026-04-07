#!/usr/bin/env python3
"""
Verifier for configure_lms_quit_integration task.

Evaluates:
1. Database confirmation that the Exam Configuration was created.
2. Database search for the specific Moodle URL indicating it was saved.
3. VLM trajectory verification to confirm the "Confirm Quit" checkbox was unchecked
   and the correct URL was typed.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_lms_quit_integration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_url = metadata.get('expected_quit_url', 'https://lms.university.edu/mod/quiz/review.php')
    expected_name = metadata.get('expected_config_name', 'Biology Final - Moodle AutoQuit')

    # Temporary files to hold the copied environment artifacts
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_sql = tempfile.NamedTemporaryFile(delete=False, suffix='.sql')

    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)

        copy_from_env("/tmp/seb_dump.sql", temp_sql.name)
        with open(temp_sql.name, 'r', encoding='utf-8', errors='ignore') as f:
            sql_dump = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load outputs from env: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_sql.name):
            os.unlink(temp_sql.name)

    score = 0
    feedback_parts = []

    # CRITERION 1: Configuration Created in Database (20 pts)
    config_exists = result.get('config_exists', False)
    new_configs_created = result.get('new_configs_created', False)

    if config_exists:
        score += 20
        feedback_parts.append(f"DB verified: Config '{expected_name}' exists.")
    else:
        feedback_parts.append(f"DB verified: Config '{expected_name}' NOT found.")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # CRITERION 2: URL Saved in Database (40 pts)
    # The URL should be serialized in the DB inside the config blob or related table
    url_found_in_db = expected_url in sql_dump
    if url_found_in_db:
        score += 40
        feedback_parts.append("DB verified: Moodle Quit URL successfully saved.")
    else:
        feedback_parts.append("DB verified: Expected Quit URL NOT found in database.")

    # CRITERION 3: VLM Trajectory Verification for UI actions (40 pts)
    # Because SEB Server DB schema maps booleans dynamically, we use robust VLM check for the "Confirm Quit" checkbox.
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        final_screenshot = get_final_screenshot(traj)
        images = frames + [final_screenshot] if final_screenshot else frames

        prompt = f"""
        You are verifying an IT administrator's actions in Safe Exam Browser Server.
        The goal was to configure the "Quit Link" settings.
        
        Examine these sequential screenshots and determine:
        1. Did the user enter the URL "{expected_url}" into a field labeled "Quit URL" or "Link to quit SEB"?
        2. Did the user uncheck/disable the setting for "Confirm Quit" or "Confirm quitting"?
        3. Did the user click Save?
        
        Return a JSON object with:
        {{
            "entered_quit_url": true/false,
            "disabled_confirm_quit": true/false,
            "clicked_save": true/false,
            "reasoning": "brief explanation"
        }}
        """
        
        vlm_res = query_vlm(images=images, prompt=prompt)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('disabled_confirm_quit', False):
            vlm_score += 30
            feedback_parts.append("VLM verified: 'Confirm Quit' disabled.")
        else:
            feedback_parts.append("VLM missing: 'Confirm Quit' not disabled.")
            
        if not url_found_in_db and parsed.get('entered_quit_url', False):
            # Partial credit if VLM saw it but DB didn't catch it
            score += 20
            feedback_parts.append("VLM verified: URL was typed (partial DB failure).")
            
        if parsed.get('clicked_save', False):
            vlm_score += 10
            feedback_parts.append("VLM verified: Save button clicked.")
            
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("VLM check encountered an error.")

    score += vlm_score

    # Final pass conditions: Must have created the config and reached a passing score threshold
    key_criteria_met = config_exists and (url_found_in_db or vlm_score > 0)
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }