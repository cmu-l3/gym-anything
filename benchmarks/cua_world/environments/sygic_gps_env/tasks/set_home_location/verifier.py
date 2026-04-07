#!/usr/bin/env python3
"""
Verifier for Sygic GPS task: set_home_location

This task requires the agent to set the "Home" location to the Eiffel Tower.
Verification uses VLM trajectory analysis to ensure the correct workflow was followed
and the final state shows the correct location.
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_home_location(traj, env_info, task_info):
    """
    Verify that the agent set the Home location to Eiffel Tower.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve artifacts from environment
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    ui_dump_path = os.path.join(temp_dir, "ui_dump.xml")
    
    task_result = {}
    ui_xml_content = ""
    
    try:
        # Get JSON result
        try:
            copy_from_env("/sdcard/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            logger.warning(f"Could not read task_result.json: {e}")

        # Get UI Dump (optional but helpful signal)
        try:
            copy_from_env("/sdcard/ui_dump.xml", ui_dump_path)
            with open(ui_dump_path, 'r', encoding='utf-8', errors='ignore') as f:
                ui_xml_content = f.read()
        except Exception as e:
            logger.warning(f"Could not read ui_dump.xml: {e}")
            
    finally:
        # Cleanup is handled by OS for temp dir, but good practice to delete files if needed
        pass

    # 2. VLM Verification Strategy
    # We need to verify the workflow and the final result.
    
    frames = sample_trajectory_frames(traj, n=6)
    final_screenshot = get_final_screenshot(traj)
    
    if not frames and not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification"}
        
    all_images = frames + [final_screenshot] if final_screenshot else frames

    # Prompt for VLM
    prompt = """
    You are verifying an Android navigation task. The agent was asked to set the "Home" location in Sygic GPS to the Eiffel Tower in Paris.
    
    Review the image sequence of the agent's actions.
    
    Check for the following steps:
    1. Did the agent open the menu (hamburger icon)?
    2. Did the agent navigate to "Manage Places", "My Places", or tap the "Home" icon to set it?
    3. Did the agent search for "Eiffel Tower", "Tour Eiffel", or similar?
    4. Did the agent select a result in Paris, France?
    5. Does the FINAL state show "Home" configured with "Eiffel Tower" or an address in Paris (e.g., Champ de Mars)?
    
    Provide a score breakdown:
    - Menu/Navigation: 20 points
    - Search for Eiffel Tower: 30 points
    - Correct selection/Setting Home: 30 points
    - Final verification (Home is set to Eiffel Tower): 20 points
    
    Fail the task if:
    - The agent set a generic favorite instead of "Home".
    - The location is completely wrong (not Eiffel Tower).
    - The agent did nothing.
    
    Respond in JSON:
    {
        "menu_opened": boolean,
        "search_performed": boolean,
        "correct_result_selected": boolean,
        "final_home_set_correctly": boolean,
        "score": number (0-100),
        "reasoning": "string"
    }
    """
    
    vlm_response = query_vlm(
        images=all_images,
        prompt=prompt
    )
    
    # 3. Text-based heuristic check (Secondary Verification)
    # Check if UI dump contains expected strings
    text_score_boost = 0
    keywords = ["Eiffel", "Tour Eiffel", "Champ de Mars", "Anatole France", "Home"]
    found_keywords = [k for k in keywords if k in ui_xml_content]
    
    # 4. Synthesize Result
    passed = False
    score = 0
    feedback = ""
    
    if vlm_response and vlm_response.get("success"):
        parsed = vlm_response.get("parsed", {})
        score = parsed.get("score", 0)
        feedback = parsed.get("reasoning", "VLM analysis complete.")
        
        # Critical checks
        if parsed.get("final_home_set_correctly"):
            passed = True
        
        # Cross-reference with text dump
        if passed and len(found_keywords) == 0:
            # If VLM says yes but XML has no relevant text, lower confidence slightly or warn
            feedback += " (Note: Expected text not found in UI dump, relying on visual confirmation.)"
        elif not passed and len(found_keywords) >= 2 and "Home" in found_keywords:
            # If VLM missed it but text is there, bump score
            score = max(score, 60)
            passed = True
            feedback += " (Text analysis confirmed Eiffel Tower set as Home, overriding VLM doubt.)"
            
    else:
        # Fallback if VLM fails completely
        if len(found_keywords) >= 2 and "Home" in found_keywords:
             score = 60
             passed = True
             feedback = "VLM failed, but UI text analysis found 'Home' and 'Eiffel Tower' keywords."
        else:
             score = 0
             passed = False
             feedback = "Verification failed: VLM analysis unavailable and text evidence missing."

    # Anti-gaming: Ensure score is 0 if app wasn't even running
    if not task_result.get("app_was_running", False):
        score = 0
        passed = False
        feedback = "Application was not running at end of task."

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }