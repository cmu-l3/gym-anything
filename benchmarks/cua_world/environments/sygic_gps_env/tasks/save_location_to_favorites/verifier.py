#!/usr/bin/env python3
"""
Verifier for save_location_to_favorites task.

Verification Strategy:
1. VLM Analysis of Trajectory:
   - Verify user searched for "Kabul Airport"
   - Verify user tapped the "Favorite/Heart" button
2. VLM Analysis of Final State:
   - Verify the Favorites list is visible
   - Verify "Kabul Airport" or "Hamid Karzai" is in the list
3. UI Dump Text Check (Secondary):
   - Check if expected text strings exist in the final UI hierarchy
"""

import json
import os
import logging
import tempfile
import re
from typing import Dict, Any, List

# Import VLM utilities from the framework
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_save_location_to_favorites(traj, env_info, task_info):
    """
    Verifies that the agent saved Kabul Airport to favorites.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_name = metadata.get('target_location_name', "Kabul Airport")
    alt_name = metadata.get('target_location_alt_name', "Hamid Karzai International Airport")

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Artifacts
    temp_dir = tempfile.mkdtemp()
    try:
        # Get result JSON
        result_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/sdcard/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # Get UI Dump
        ui_dump_path = os.path.join(temp_dir, "ui_dump.xml")
        ui_dump_content = ""
        if result_data.get("ui_dump_exists"):
            try:
                copy_from_env("/sdcard/ui_dump.xml", ui_dump_path)
                with open(ui_dump_path, 'r', errors='ignore') as f:
                    ui_dump_content = f.read()
            except Exception:
                pass

    finally:
        # Cleanup is handled by system, but good practice to delete specific files if large
        pass

    # 2. Text Verification (UI Dump) - 30 Points
    # This is a strong signal if the UI renders as native views
    text_score = 0
    found_target_text = False
    
    if ui_dump_content:
        # Check for presence of target keywords
        if "Kabul" in ui_dump_content or "Hamid Karzai" in ui_dump_content:
            text_score += 15
            found_target_text = True
            feedback_parts.append("Target location name found in UI text")
        
        if "Favorite" in ui_dump_content or "Favorites" in ui_dump_content:
            text_score += 15
            feedback_parts.append("Favorites header/label found in UI text")
    
    score += text_score

    # 3. VLM Trajectory Verification - 70 Points
    # We rely on VLM to understand the visual workflow
    
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    if not frames and not final_screen:
        return {"passed": False, "score": score, "feedback": "No visual evidence available"}

    # Prompt for VLM
    prompt = f"""
    You are verifying an agent's interaction with a GPS navigation app (Sygic).
    
    Goal: Search for "{target_name}" and add it to Favorites. Finally, show the Favorites list.
    
    Review the image sequence (trajectory) and the final screen.
    
    Check for these specific milestones:
    1. SEARCH: Did the agent type "{target_name}" or "{alt_name}" in a search bar?
    2. SELECTION: Did the agent select a result matching the airport?
    3. SAVE: Did the agent tap a "Heart", "Star", or "Add to Favorites" button on a location detail screen?
    4. VERIFICATION: Does the FINAL screenshot show a list of Favorites/Places?
    5. SUCCESS: Is "{target_name}" or "{alt_name}" visible in that list in the final screenshot?
    
    Provide a JSON response with:
    - search_performed (bool)
    - save_action_observed (bool)
    - favorites_list_visible (bool)
    - target_in_list (bool)
    - confidence (0.0 to 1.0)
    """
    
    # Query VLM
    vlm_result = query_vlm(images=frames + [final_screen], prompt=prompt)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # Scoring logic based on VLM
        if parsed.get("search_performed"):
            score += 15
            feedback_parts.append("VLM: Search performed")
            
        if parsed.get("save_action_observed"):
            score += 20
            feedback_parts.append("VLM: Save action observed")
            
        if parsed.get("favorites_list_visible"):
            score += 15
            feedback_parts.append("VLM: Favorites list visible")
            
        if parsed.get("target_in_list"):
            score += 20
            feedback_parts.append("VLM: Target found in Favorites list")
            
    else:
        feedback_parts.append("VLM verification failed to process")

    # Final Adjustment: If text verification found the item, ensure we get points for "target_in_list"
    # even if VLM missed it (or vice versa)
    if found_target_text and not any("Target found" in f for f in feedback_parts):
         score += 20
         feedback_parts.append("Text verification confirmed target in list")

    # Cap score at 100
    score = min(100, score)
    
    # Pass threshold
    # Must have saved it (action) + see it in list (visual or text)
    passed = score >= 65 and (parsed.get("target_in_list", False) or found_target_text)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }