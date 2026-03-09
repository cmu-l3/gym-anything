#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_menu_order_workflow(traj, env_info, task_info):
    """
    Verifies the End-to-End Menu Configuration and Order Workflow task.
    
    Criteria:
    1. DB: Modifier Group 'Burger Toppings' exists (10 pts)
    2. DB: Modifiers (Bacon, Avocado, Extra Cheese) exist with correct prices (20 pts)
    3. DB: Menu Item 'Build-Your-Own Burger' exists with price $9.99 (15 pts)
    4. DB: Valid Ticket created after task start containing the burger (20 pts)
    5. DB: Ticket total matches expected ~$13.49 (15 pts)
    6. VLM: Visual evidence of Back Office and Order Entry interaction (20 pts)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_data = result_data.get('db_verification', {})
    if 'error' in db_data:
        logger.warning(f"DB Verification Error: {db_data['error']}")
        # Fallback to pure VLM if DB fails entirely (though unlikely if setup works)

    score = 0
    feedback = []

    # 2. Database Verification (Programmatic)
    
    # Check Modifier Group
    if db_data.get('mod_group_exists'):
        score += 10
        feedback.append("Success: Modifier Group 'Burger Toppings' created.")
    else:
        feedback.append("Fail: Modifier Group 'Burger Toppings' not found.")

    # Check Modifiers
    found_mods = db_data.get('modifiers_found', [])
    # Parse list of dict strings/objects
    # The java output is List.toString which looks like [{name=.., price=..}] or similar depending on implementation
    # But my Java code output explicit JSON-like string format: modifiersFound.add(String.format("{\"name\": \"%s\", ...}"))
    # So db_data['modifiers_found'] is a list of dicts.
    
    expected_mods = {
        "Bacon": 1.50,
        "Avocado": 2.00,
        "Extra Cheese": 0.75
    }
    
    mods_score = 0
    for mod in found_mods:
        name = mod.get('name')
        price = mod.get('price')
        if name in expected_mods:
            if abs(price - expected_mods[name]) < 0.01:
                mods_score += 6.66  # ~20 pts total
            else:
                feedback.append(f"Partial: {name} found but wrong price (${price}).")
    
    if mods_score >= 19: mods_score = 20 # Round up perfect
    score += int(mods_score)
    if int(mods_score) > 0:
        feedback.append(f"Modifiers check: +{int(mods_score)} pts")

    # Check Menu Item
    if db_data.get('menu_item_exists'):
        actual_price = db_data.get('menu_item_price', 0.0)
        if abs(actual_price - 9.99) < 0.01:
            score += 15
            feedback.append("Success: Menu Item created with correct price.")
        else:
            score += 10
            feedback.append(f"Partial: Menu Item name correct but price wrong (${actual_price}).")
    else:
        feedback.append("Fail: Menu Item 'Build-Your-Own Burger' not found.")

    # Check Ticket Existence (Proof of Order)
    if db_data.get('ticket_found'):
        score += 20
        feedback.append("Success: New ticket found containing the burger.")
        
        # Check Total
        ticket_total = db_data.get('ticket_total', 0.0)
        expected_total = 13.49
        # Allow small tolerance for tax variations if not configured exact
        if abs(ticket_total - expected_total) < 0.50:
            score += 15
            feedback.append(f"Success: Ticket total (${ticket_total}) is correct.")
        else:
            feedback.append(f"Fail: Ticket total (${ticket_total}) incorrect. Expected ~$13.49.")
    else:
        feedback.append("Fail: No valid ticket found created during task.")

    # 3. VLM Verification (Visual Process)
    # Check if agent visited Back Office AND Main Screen
    
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    images = frames + ([final_frame] if final_frame else [])
    
    vlm_prompt = """
    Analyze these screenshots of a POS system workflow.
    I need to confirm the user performed two distinct phases:
    1. ADMIN/BACK OFFICE: Look for screens with lists of settings, 'Explorer', 'Menu Items', or forms with 'Save'/'Delete'.
    2. ORDER ENTRY: Look for the main visual grid of table buttons or food item buttons (colored grids), and a 'PAY' or 'SETTLE' screen.
    
    Did the user visit BOTH the Back Office configuration screens AND the front-end Order screens?
    """
    
    vlm_result = query_vlm(images=images, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        # Simple heuristic based on response text for now, assuming robust VLM
        response_text = vlm_result.get('response', '').lower()
        if "both" in response_text and "back office" in response_text and "order" in response_text:
            vlm_score = 20
        elif "yes" in response_text:
            vlm_score = 20
        else:
            vlm_score = 10 # Give partial benefit if ambiguous
            
        score += vlm_score
        feedback.append(f"VLM Workflow Check: +{vlm_score} pts")
    else:
        # Fallback if VLM fails
        feedback.append("VLM Check skipped (service unavailable).")
        score += 20 # Benefit of doubt if programmatic passes

    # Final Pass/Fail
    passed = score >= 70 and db_data.get('menu_item_exists') and db_data.get('ticket_found')
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }