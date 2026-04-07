#!/usr/bin/env python3
"""
Verifier for create_custom_checklist task in Avare.
Uses VLM to verify the visual state of the checklist and checks internal data persistence.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utilities from the framework
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_checklist(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify creation of C172 Runup checklist.
    
    Criteria:
    1. Visual Verification (VLM):
       - Checklist screen is visible
       - Title "C172 Runup" is visible
       - Items "Doors Closed", "Mags Both", "Carb Heat Cold" are visible
    2. Persistence Verification (File check):
       - Strings found in app data (if accessible)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', 'C172 Runup')
    expected_items = metadata.get('expected_items', [])

    # 1. Retrieve Result JSON from device
    task_result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json") as tmp:
            copy_from_env("/sdcard/task_result.json", tmp.name)
            tmp.seek(0)
            task_result = json.load(tmp)
    except Exception as e:
        logger.warning(f"Could not retrieve task_result.json: {e}")

    # 2. Retrieve Screenshot
    final_screenshot = get_final_screenshot(traj)
    
    # 3. VLM Verification
    vlm_score = 0
    vlm_feedback = []
    
    if final_screenshot:
        prompt = f"""
        You are verifying an agent's task in an aviation app.
        The goal was to create a checklist titled '{expected_title}' with these items:
        {', '.join(expected_items)}.

        Look at the screenshot and answer:
        1. Is the user viewing a Checklist screen?
        2. Is the title '{expected_title}' visible?
        3. Are the items 'Doors Closed', 'Mags Both', and 'Carb Heat Cold' visible?
        
        Output JSON:
        {{
            "is_checklist_screen": boolean,
            "title_visible": boolean,
            "items_visible_count": integer (0-3),
            "reasoning": "string"
        }}
        """
        
        response = query_vlm(
            prompt=prompt,
            image=final_screenshot
        )
        
        if response.get('success'):
            parsed = response.get('parsed', {})
            logger.info(f"VLM Analysis: {parsed}")
            
            if parsed.get('is_checklist_screen'):
                vlm_score += 20
                vlm_feedback.append("Checklist screen active")
            
            if parsed.get('title_visible'):
                vlm_score += 30
                vlm_feedback.append(f"Title '{expected_title}' found")
            else:
                vlm_feedback.append(f"Title '{expected_title}' NOT found")
                
            items_count = parsed.get('items_visible_count', 0)
            # 15 points per item, max 45
            item_score = min(items_count * 15, 45)
            vlm_score += item_score
            vlm_feedback.append(f"Found {items_count}/3 items")
            
        else:
            vlm_feedback.append("VLM analysis failed")
    else:
        vlm_feedback.append("No screenshot available")

    # 4. Persistence Verification (Bonus/Backup)
    persistence = task_result.get('persistence_check', {})
    persistence_score = 0
    
    if persistence.get('title_found'):
        persistence_score += 5
        vlm_feedback.append("Persistence: Title found in storage")
    
    # Calculate Total
    total_score = min(vlm_score + persistence_score, 100)
    
    # Pass logic: Must have title visible AND at least 2 items visible (via VLM) 
    # OR Title visible via VLM + persistence confirmed
    
    passed = False
    is_checklist_screen = response.get('parsed', {}).get('is_checklist_screen', False) if response.get('success') else False
    title_visible = response.get('parsed', {}).get('title_visible', False) if response.get('success') else False
    items_count = response.get('parsed', {}).get('items_visible_count', 0) if response.get('success') else 0
    
    if is_checklist_screen and title_visible and items_count >= 2:
        passed = True
    elif is_checklist_screen and title_visible and persistence.get('title_found'):
        # Fallback if OCR misses items but file check confirms title
        passed = True
        
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(vlm_feedback),
        "details": {
            "vlm_parsed": response.get('parsed', {}) if response.get('success') else None,
            "persistence": persistence
        }
    }