#!/usr/bin/env python3
"""
Verifier for search_poi_near_destination task.

Task: Search for "Kabul", then find "Hospitals" near that location.

Verification Strategy:
1. VLM Trajectory Analysis (PRIMARY):
   - Confirm the agent searched for "Kabul" (context switching).
   - Confirm the agent selected "Hospital" category.
   - Confirm the final view shows hospitals in Kabul.
2. UI Text Analysis (SECONDARY):
   - Check if keywords "Hospital" and "Kabul" appear on the final screen.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_search_poi_near_destination(traj, env_info, task_info):
    """
    Verify the agent found hospitals near the specific destination (Kabul).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Retrieve Data from Environment
    # ================================================================
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    ui_dump_path = os.path.join(temp_dir, "ui_dump.xml")

    try:
        copy_from_env("/sdcard/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
        
        # Try to copy UI dump, but don't fail if missing
        try:
            copy_from_env("/sdcard/ui_dump.xml", ui_dump_path)
            with open(ui_dump_path, 'r', encoding='utf-8', errors='ignore') as f:
                ui_content = f.read()
        except Exception:
            ui_content = ""
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}
    finally:
        # Cleanup handled by tempfile logic usually, but explicit removal is good
        pass

    score = 0
    feedback_parts = []
    
    # Check basic app state
    if result_data.get("app_running", False):
        score += 10
        feedback_parts.append("App is running")
    else:
        feedback_parts.append("App crashed or closed")

    # ================================================================
    # 2. VLM Trajectory Analysis (Crucial for Context)
    # ================================================================
    # We need to distinguish between "Hospitals near me" (wrong) and "Hospitals in Kabul" (correct).
    # Trajectory must show the search for Kabul.
    
    frames = sample_trajectory_frames(traj, n=5)
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {"passed": False, "score": score, "feedback": "No final screenshot available"}

    vlm_prompt = """
    Analyze this sequence of interactions in a GPS navigation app.
    The user's goal is to find 'Hospitals' specifically in 'Kabul, Afghanistan' (NOT near the current location).
    
    Check for these steps:
    1. Did the user search for the city 'Kabul' or 'Kabul, Afghanistan'?
    2. Did the user select 'Kabul' from the results?
    3. Did the user select a 'Hospital' or 'Health' category?
    4. Does the FINAL screenshot show a list of hospitals or map pins in Kabul? (Look for text like 'Aliabad', 'French Medical', 'Kabul', or distances relative to a city center).
    
    Return JSON:
    {
        "searched_for_kabul": boolean,
        "selected_hospital_category": boolean,
        "final_view_shows_hospitals": boolean,
        "final_context_is_kabul": boolean,
        "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(
        images=frames + [final_screenshot],
        prompt=vlm_prompt
    )
    
    vlm_data = vlm_result.get("parsed", {})
    logger.info(f"VLM Analysis: {vlm_data}")
    
    # Scoring based on VLM
    if vlm_data.get("searched_for_kabul", False):
        score += 25
        feedback_parts.append("Agent searched for destination city")
    else:
        feedback_parts.append("Failed to identify city search step")

    if vlm_data.get("selected_hospital_category", False):
        score += 25
        feedback_parts.append("Agent selected Hospital category")

    if vlm_data.get("final_view_shows_hospitals", False):
        score += 20
        feedback_parts.append("Hospitals visible in final view")
        
    if vlm_data.get("final_context_is_kabul", False):
        score += 20
        feedback_parts.append("Context confirms Kabul location")
    else:
        feedback_parts.append("Could not confirm results are for Kabul (might be local results)")

    # ================================================================
    # 3. Secondary UI Dump Check (Text verification)
    # ================================================================
    # Check for specific Kabul hospitals or the word "Kabul" in the result list
    # Common hospitals in Sygic for Kabul: "Aliabad", "French Medical", "Wazir Akbar Khan"
    
    keywords_found = 0
    keyword_score = 0
    
    if ui_content:
        lower_content = ui_content.lower()
        if "kabul" in lower_content:
            keywords_found += 1
        if "hospital" in lower_content or "medical" in lower_content or "health" in lower_content:
            keywords_found += 1
            
        # If we have UI dump, we can validate the VLM's visual assessment
        if keywords_found >= 2:
            # Boost score if VLM was unsure but text confirms it
            if not vlm_data.get("final_context_is_kabul", False):
                score += 10
                feedback_parts.append("Text analysis confirms Kabul context")
    
    # Pass logic
    # strict pass: must have searched for city AND found hospitals in that context
    passed = (
        vlm_data.get("searched_for_kabul", False) and 
        vlm_data.get("final_view_shows_hospitals", False) and
        (vlm_data.get("final_context_is_kabul", False) or keywords_found >= 2) and
        score >= 70
    )

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": vlm_data
    }