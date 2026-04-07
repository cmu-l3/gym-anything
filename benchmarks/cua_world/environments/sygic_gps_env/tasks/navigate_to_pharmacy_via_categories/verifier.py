#!/usr/bin/env python3
"""
Verifier for navigate_to_pharmacy_via_categories task.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_category_navigation(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that the agent navigated to a pharmacy using the category browser.
    
    Criteria:
    1. Workflow: User accessed "Categories/Places" menu (VLM).
    2. Constraint: User did NOT use keyboard text search (VLM).
    3. Outcome: Final screen shows active navigation to a Pharmacy (VLM + UI Dump).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve artifacts from environment
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    ui_dump_path = os.path.join(temp_dir, "window_dump.xml")
    
    try:
        copy_from_env("/sdcard/tasks/navigate_to_pharmacy_via_categories/task_result.json", result_json_path)
        copy_from_env("/sdcard/tasks/navigate_to_pharmacy_via_categories/window_dump.xml", ui_dump_path)
        
        with open(result_json_path, 'r') as f:
            task_result = json.load(f)
            
        ui_xml_content = ""
        if os.path.exists(ui_dump_path):
            with open(ui_dump_path, 'r', encoding='utf-8', errors='ignore') as f:
                ui_xml_content = f.read()
                
    except Exception as e:
        logger.error(f"Failed to copy/read artifacts: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        # Cleanup is handled by OS for temp dir usually, or explicit removal if needed
        pass

    # 2. VLM Verification Strategy
    # We need to look at the trajectory to confirm the METHOD (Categories) vs (Search)
    frames = sample_trajectory_frames(traj, n=6)
    final_screenshot = get_final_screenshot(traj)
    
    if not frames or not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No video evidence available"}

    # Prompt designed to check both workflow and outcome
    prompt = """
    You are verifying an Android navigation task. 
    Goal: Find a 'Pharmacy' using the 'Categories' browsing menu (icons), NOT by typing 'Pharmacy' in the search bar.
    
    Analyze the image sequence:
    1. Did the user open a menu showing Category icons (like Gas, Parking, Food, Health, Shop)?
    2. Did the user select a 'Pharmacy' or 'Health/Medical' category?
    3. Did the user TYPE 'Pharmacy' on a keyboard? (This is FORBIDDEN).
    4. Does the FINAL image show active navigation (Turn-by-turn mode, map tilted, distance/time remaining)?
    5. Does the destination in the final image appear to be a pharmacy (look for names like 'Pharmacy', 'Drugstore', 'Deryatoon', or 'Medic')?
    
    Respond in JSON:
    {
        "category_menu_opened": boolean,
        "pharmacy_category_selected": boolean,
        "keyboard_used_to_search": boolean,
        "navigation_active": boolean,
        "destination_is_pharmacy": boolean,
        "confidence": "high/medium/low",
        "reasoning": "string"
    }
    """
    
    vlm_response = query_vlm(images=frames + [final_screenshot], prompt=prompt)
    
    if not vlm_response.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed"}
        
    analysis = vlm_response.get("parsed", {})
    
    # 3. Text-based Backup Verification (XML)
    # Check if "Pharmacy" or related keywords exist in the final UI dump
    xml_keywords = ["Pharmacy", "Drugstore", "Medic", "Health"]
    xml_confirms_pharmacy = any(k.lower() in ui_xml_content.lower() for k in xml_keywords)
    
    # 4. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion A: Workflow - Opened Categories (25 pts)
    if analysis.get("category_menu_opened"):
        score += 25
        feedback_parts.append("Correctly used category menu.")
    else:
        feedback_parts.append("Did not see category menu opened.")

    # Criterion B: Workflow - Found Pharmacy Category (25 pts)
    if analysis.get("pharmacy_category_selected"):
        score += 25
        feedback_parts.append("Selected Pharmacy category.")
    
    # Criterion C: Constraint - No Keyboard Search (10 pts)
    if not analysis.get("keyboard_used_to_search"):
        score += 10
        feedback_parts.append("Followed constraint (no typing).")
    else:
        feedback_parts.append("PENALTY: Used keyboard search instead of browsing.")

    # Criterion D: Outcome - Active Navigation to Pharmacy (40 pts)
    nav_active = analysis.get("navigation_active")
    dest_pharmacy = analysis.get("destination_is_pharmacy") or xml_confirms_pharmacy
    
    if nav_active and dest_pharmacy:
        score += 40
        feedback_parts.append("Successfully started navigation to a pharmacy.")
    elif nav_active:
        score += 20
        feedback_parts.append("Started navigation, but destination unclear.")
    elif dest_pharmacy:
        score += 10
        feedback_parts.append("Found pharmacy but did not start navigation.")
    else:
        feedback_parts.append("Failed to start navigation to pharmacy.")

    # Final Pass/Fail
    # Must have used categories AND reached navigation
    passed = (score >= 70) and analysis.get("category_menu_opened") and nav_active

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": analysis
    }