#!/usr/bin/env python3
"""
Verifier for setup_starting_balances task.

Criteria:
1. Start Date must be 2024-07-01 (15 pts)
2. Cash on Hand balance: 25,000.00 (20 pts)
3. AR - Alfreds Futterkiste: 3,200.00 (15 pts)
4. AR - Ernst Handel: 5,300.00 (15 pts)
5. AP - Exotic Liquids: 4,750.00 (15 pts)
6. VLM Verification of workflow (20 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_starting_balances(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_date = metadata.get('expected_start_date', "2024-07-01")
    expected_balances = metadata.get('expected_balances', {})

    # Copy result file
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

    scraped = result.get('scraped_data', {})
    actual_balances = scraped.get('balances', {})
    actual_date = scraped.get('start_date')

    score = 0
    feedback = []
    
    # 1. Check Start Date (15 pts)
    if actual_date == expected_date:
        score += 15
        feedback.append(f"Start Date correct ({actual_date})")
    else:
        feedback.append(f"Start Date incorrect. Expected {expected_date}, got {actual_date}")

    # 2. Check Cash on Hand (20 pts)
    # Using small epsilon for float comparison
    cash_val = actual_balances.get("Cash on Hand", 0.0)
    if abs(cash_val - expected_balances["Cash on Hand"]) < 0.01:
        score += 20
        feedback.append("Cash on Hand correct")
    else:
        feedback.append(f"Cash on Hand incorrect: {cash_val}")

    # 3. Check Alfreds Futterkiste (15 pts)
    alfreds_val = actual_balances.get("Alfreds Futterkiste", 0.0)
    if abs(alfreds_val - expected_balances["Accounts receivable — Alfreds Futterkiste"]) < 0.01:
        score += 15
        feedback.append("Alfreds Futterkiste correct")
    else:
        feedback.append(f"Alfreds Futterkiste incorrect: {alfreds_val}")

    # 4. Check Ernst Handel (15 pts)
    ernst_val = actual_balances.get("Ernst Handel", 0.0)
    if abs(ernst_val - expected_balances["Accounts receivable — Ernst Handel"]) < 0.01:
        score += 15
        feedback.append("Ernst Handel correct")
    else:
        feedback.append(f"Ernst Handel incorrect: {ernst_val}")

    # 5. Check Exotic Liquids (15 pts)
    exotic_val = actual_balances.get("Exotic Liquids", 0.0)
    if abs(exotic_val - expected_balances["Accounts payable — Exotic Liquids"]) < 0.01:
        score += 15
        feedback.append("Exotic Liquids correct")
    else:
        feedback.append(f"Exotic Liquids incorrect: {exotic_val}")

    # 6. VLM Verification (20 pts)
    # We check if the agent actually navigated to Settings and the specific forms
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = """
        You are verifying a user setting up accounting software.
        Look at these screenshots. 
        Did the user:
        1. Navigate to a 'Settings' screen?
        2. Access a 'Start Date' form?
        3. Access a 'Starting Balances' form?
        
        Answer JSON: {"settings_visited": bool, "start_date_form": bool, "starting_balances_form": bool}
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
            vlm_data = vlm_res.get('parsed', {})
            
            vlm_score = 0
            if vlm_data.get('settings_visited'): vlm_score += 5
            if vlm_data.get('start_date_form'): vlm_score += 5
            if vlm_data.get('starting_balances_form'): vlm_score += 10
            
            score += vlm_score
            if vlm_score > 0:
                feedback.append(f"VLM verified workflow ({vlm_score}/20 pts)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if programmatic passed, give VLM points partially
            if score >= 80:
                score += 20
                feedback.append("VLM skipped but data correct (+20)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback)
    }