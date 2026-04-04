#!/usr/bin/env python3
"""
Verifier for configure_service_catalog task.

Checks:
1. 'Hardware Services' category exists in DB.
2. 'New Laptop Request' item exists in DB.
3. Descriptions match keywords.
4. Counts increased (anti-gaming).
5. VLM verification of UI workflow.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_service_catalog(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_cat_keywords = metadata.get('expected_category_desc_keywords', [])
    expected_item_keywords = metadata.get('expected_item_desc_keywords', [])

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Database Verification (60 points)
    # Category Check (25 pts)
    if result.get('category_found', False):
        score += 20
        feedback.append("Service Category 'Hardware Services' created.")
        
        # Check description content
        cat_details = result.get('category_details', '').lower()
        matches = [kw for kw in expected_cat_keywords if kw.lower() in cat_details]
        if len(matches) >= 1:
            score += 5
            feedback.append("Category description verified.")
        else:
            feedback.append("Category description missing keywords.")
    else:
        feedback.append("Service Category 'Hardware Services' NOT found.")

    # Item Check (25 pts)
    if result.get('item_found', False):
        score += 20
        feedback.append("Service Item 'New Laptop Request' created.")
        
        # Check description content
        item_details = result.get('item_details', '').lower()
        matches = [kw for kw in expected_item_keywords if kw.lower() in item_details]
        if len(matches) >= 1:
            score += 5
            feedback.append("Item description verified.")
        else:
            feedback.append("Item description missing keywords.")
    else:
        feedback.append("Service Item 'New Laptop Request' NOT found.")

    # Anti-gaming: Count check (10 pts)
    counts = result.get('counts', {})
    if counts.get('final_cat', 0) > counts.get('initial_cat', 0) and \
       counts.get('final_item', 0) > counts.get('initial_item', 0):
        score += 10
        feedback.append("New records confirmed added during task session.")
    elif result.get('category_found') and result.get('item_found'):
        # If found but counts didn't move, maybe they existed or were renamed. 
        # We give partial credit if exact names match.
        score += 5
        feedback.append("Records found but count verification ambiguous.")

    # 2. VLM Verification (30 points)
    # We verify the workflow: Admin -> Service Catalog -> Add Category/Item
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user configuring ManageEngine ServiceDesk Plus.
    I am looking for:
    1. Navigation to the 'Service Catalog' configuration in the Admin section.
    2. A form being filled out for a Service Category named 'Hardware Services'.
    3. A form being filled out for a Service Item named 'New Laptop Request'.
    4. The final result showing these items in the list.
    
    Return JSON:
    {
        "admin_navigation_visible": true/false,
        "category_creation_visible": true/false,
        "item_creation_visible": true/false,
        "final_list_visible": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        vlm_data = vlm_res.get('parsed', {})
        
        vlm_score = 0
        if vlm_data.get('category_creation_visible'): vlm_score += 10
        if vlm_data.get('item_creation_visible'): vlm_score += 10
        if vlm_data.get('final_list_visible'): vlm_score += 10
        
        score += vlm_score
        if vlm_score > 0:
            feedback.append(f"VLM verified workflow steps ({vlm_score} pts).")
    except Exception as e:
        logger.error(f"VLM error: {e}")
        feedback.append("VLM verification failed to run.")

    # Final Pass Logic
    # Must have created both Category and Item in DB to pass
    passed = result.get('category_found', False) and result.get('item_found', False) and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }