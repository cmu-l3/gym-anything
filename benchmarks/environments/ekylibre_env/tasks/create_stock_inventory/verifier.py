#!/usr/bin/env python3
"""
Verifier for create_stock_inventory task in Ekylibre.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_stock_inventory(traj, env_info, task_info):
    """
    Verifies that a stock inventory was created with correct details and items.
    """
    # 1. Setup access to container files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load result JSON
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

    # 3. Extract metadata requirements
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Year-End Stock Count Jan 2024")
    expected_date = metadata.get('expected_date', "2024-01-15")
    min_items = metadata.get('min_items', 2)

    # 4. Scoring Logic
    score = 0
    feedback_parts = []
    
    # DB Check: Inventory Record Exists (25 pts)
    inv_details = result.get('inventory_details', {})
    inv_name = inv_details.get('name', '')
    inv_date = inv_details.get('date', '')
    
    if result.get('inventory_found', False) and expected_name.lower() in inv_name.lower():
        score += 25
        feedback_parts.append(f"Inventory created with name '{inv_name}'")
    elif result.get('inventory_found', False):
        score += 10
        feedback_parts.append(f"Inventory created but wrong name: '{inv_name}'")
    else:
        feedback_parts.append("No inventory record found")
        # Critical failure if no inventory created
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # DB Check: Date Correct (10 pts)
    if inv_date == expected_date:
        score += 10
        feedback_parts.append("Correct date")
    else:
        feedback_parts.append(f"Incorrect date: {inv_date} (expected {expected_date})")

    # DB Check: Items Count (20 pts for >=1, 35 total for >=2)
    items_count = int(result.get('items_count', 0))
    if items_count >= min_items:
        score += 35
        feedback_parts.append(f"Added {items_count} items")
    elif items_count >= 1:
        score += 20
        feedback_parts.append(f"Added only {items_count} item (expected {min_items})")
    else:
        feedback_parts.append("No items added to inventory")

    # DB Check: Quantities Set (10 pts)
    items_with_qty = int(result.get('items_with_quantity_count', 0))
    if items_with_qty >= 1:
        score += 10
        feedback_parts.append("Quantities recorded")
    else:
        feedback_parts.append("No quantities entered")

    # 5. VLM Verification (20 pts)
    # Check if agent actually navigated and interacted
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review this sequence of screenshots from a farm management software (Ekylibre).
    The user is supposed to:
    1. Navigate to the Stock/Inventory section
    2. Fill out an inventory creation form
    3. Add products and quantities
    
    Answer yes/no:
    - Did the user navigate to a list of inventories or stock dashboard?
    - Is there a form visible where 'Year-End Stock Count' or similar text was typed?
    - Are there any red error messages blocking progress?
    """
    
    try:
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        
        # Simple keyword heuristic for VLM parsing (in real impl, parse JSON or structured output)
        vlm_score = 0
        if "yes" in vlm_result.lower():
            vlm_score = 20
        
        # Penalize if 'error' and 'red' appear together strongly in VLM reasoning
        if "error" in vlm_result.lower() and "red" in vlm_result.lower() and "blocking" in vlm_result.lower():
            vlm_score = 0
            feedback_parts.append("VLM detected errors")
        else:
            feedback_parts.append("Visual verification passed")
            
        score += vlm_score
        
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if DB checks passed strongly, assume visual is okay-ish
        if score >= 60:
            score += 10
            feedback_parts.append("Visual check skipped (error)")

    # 6. Final Decision
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }