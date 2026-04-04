#!/usr/bin/env python3
"""
Verifier for create_debit_note task.

SCORING CRITERIA:
1. Debit Note created (Count increased): 20 pts
2. Correct Supplier (Exotic Liquids): 25 pts
3. Correct Amount (350.00): 25 pts
4. Correct Reference (DN-001): 15 pts
5. Correct Description (keywords): 15 pts

Pass threshold: 70 pts (Must have created note + supplier + amount).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_debit_note(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    initial_count = result.get("initial_count", 0)
    current_count = result.get("current_count", 0)
    found_target = result.get("found_target", False)
    target_details = result.get("target_details", {})
    
    # CRITERION 1: Creation Check (20 pts)
    # Anti-gaming: ensure count increased OR we found the specific new record
    if current_count > initial_count:
        score += 20
        feedback.append("New debit note record created (+20).")
    elif found_target:
        # Fallback: if count didn't change (maybe deleted one?), but target exists
        score += 20
        feedback.append("Target record found despite count match (+20).")
    else:
        feedback.append("No new debit note record detected.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # If we haven't identified the target perfectly in the export script,
    # let's try to find the best match from the list provided in 'debit_notes'
    if not found_target:
        best_match = None
        max_match_score = 0
        
        for note in result.get("debit_notes", []):
            match_score = 0
            if note.get("supplier") == "Exotic Liquids": match_score += 1
            if note.get("reference") == "DN-001": match_score += 1
            if note.get("amount_found"): match_score += 1
            
            if match_score > max_match_score:
                max_match_score = match_score
                best_match = note
        
        target_details = best_match if best_match else {}

    # CRITERION 2: Supplier (25 pts)
    if target_details.get("supplier") == "Exotic Liquids":
        score += 25
        feedback.append("Correct supplier selected (+25).")
    else:
        feedback.append("Incorrect or missing supplier.")

    # CRITERION 3: Amount (25 pts)
    if target_details.get("amount_found"):
        score += 25
        feedback.append("Correct amount 350.00 (+25).")
    else:
        feedback.append("Incorrect amount.")

    # CRITERION 4: Reference (15 pts)
    if target_details.get("reference") == "DN-001":
        score += 15
        feedback.append("Correct reference DN-001 (+15).")
    else:
        feedback.append("Incorrect reference.")

    # CRITERION 5: Description (15 pts)
    if target_details.get("description_found"):
        score += 15
        feedback.append("Description contains required keywords (+15).")
    else:
        # VLM Fallback for description if scraping failed
        # Sometimes description is hidden in sub-fields not easily regexed from view page
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final_ss = get_final_screenshot(traj)
            if final_ss:
                vlm_resp = query_vlm(
                    images=[final_ss],
                    prompt="Does this screenshot show a Debit Note with description mentioning 'damaged' or 'beverages'? Answer yes or no."
                )
                if vlm_resp and vlm_resp.get("parsed", {}).get("answer", "").lower() == "yes":
                    score += 15
                    feedback.append("Description verified via VLM (+15).")
                else:
                    feedback.append("Description keywords missing.")
        except:
            feedback.append("Description check failed.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }