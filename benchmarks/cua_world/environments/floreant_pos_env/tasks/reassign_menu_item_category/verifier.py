#!/usr/bin/env python3
"""
Verifier for reassign_menu_item_category task.

Task: Reassign "Garlic Naan" from "ENTREE" to "SIDES" category.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import shared VLM utils if available in the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reassign_menu_item_category(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the agent reassigned the menu item correctly.
    
    Criteria:
    1. 'Garlic Naan' exists in DB (20 pts)
    2. Category ID matches 'SIDES' ID (50 pts)
    3. Category Name matches 'SIDES' (Alternative check if ID fails)
    4. Price was NOT changed (Anti-collateral damage) (10 pts)
    5. App was running/activity detected (10 pts)
    6. VLM Verification of UI interaction (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    # 1. Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Data extraction
    naan_exists = result.get("naan_exists", False)
    current_cat_id = str(result.get("current_category_id", "-1")).strip()
    current_cat_name = str(result.get("current_category_name", "")).strip().upper()
    expected_sides_id = str(result.get("expected_sides_id", "-2")).strip()
    expected_entree_id = str(result.get("expected_entree_id", "-3")).strip()
    price_changed = result.get("price_changed", False)
    app_running = result.get("app_was_running", False)

    # CRITERION 1: Item Exists (20 pts)
    if naan_exists:
        score += 20
        feedback.append("Item 'Garlic Naan' found in database.")
    else:
        feedback.append("FAIL: 'Garlic Naan' item is missing from database.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # CRITERION 2: Category Reassigned (50 pts)
    # Check ID match or Name match (robustness)
    cat_match = False
    if current_cat_id == expected_sides_id:
        cat_match = True
    elif "SIDES" in current_cat_name:
        cat_match = True
        
    if cat_match:
        score += 50
        feedback.append("Category correctly changed to SIDES.")
    elif current_cat_id == expected_entree_id:
        feedback.append("FAIL: Item is still in ENTREE category.")
    else:
        feedback.append(f"FAIL: Item is in unexpected category (ID: {current_cat_id}, Name: {current_cat_name}).")

    # CRITERION 3: No Collateral Damage (10 pts)
    if not price_changed:
        score += 10
        feedback.append("Item details preserved.")
    else:
        feedback.append("WARN: Item price was modified unintentionally.")

    # CRITERION 4: App Running/Timestamp (10 pts)
    if app_running:
        score += 10
    else:
        feedback.append("Note: App was closed before verification (acceptable if task done).")

    # CRITERION 5: VLM Verification (10 pts)
    # Use trajectory to verify they actually used the UI
    vlm_score = 0
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            prompt = """
            Review these screenshots of a Point of Sale (POS) system task.
            The user should be:
            1. Entering a Back Office menu (pin pad login).
            2. Editing a menu item (changing 'Garlic Naan' category).
            
            Do you see the 'Menu Item' editor or a list of items being accessed?
            Answer yes if the workflow seems consistent with editing a menu item.
            """
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get("success") and "yes" in vlm_res.get("response", "").lower():
                vlm_score = 10
                feedback.append("Visual workflow verification passed.")
            else:
                feedback.append("Visual verification inconclusive.")
        except Exception:
            # Fallback if VLM fails or empty trajectory
            vlm_score = 10 if score >= 70 else 0
    else:
        # Fallback if VLM not loaded
        vlm_score = 10 if score >= 70 else 0
        
    score += vlm_score

    # Determine Pass/Fail
    # Must have changed category + item exists
    passed = (score >= 80) and cat_match and naan_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }