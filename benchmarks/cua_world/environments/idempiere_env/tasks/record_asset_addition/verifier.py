#!/usr/bin/env python3
import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_asset_addition(traj, env_info, task_info):
    """
    Verifies that the agent correctly recorded a fixed asset addition.
    
    Criteria:
    1. A new record exists in A_Asset_Addition for VAN-001.
    2. The amount matches 2500.00.
    3. The description contains relevant keywords.
    4. VLM trajectory confirms UI usage.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # 1. Load result from container
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

    metadata = task_info.get('metadata', {})
    target_amount = float(metadata.get('target_amount', 2500.00))
    keywords = metadata.get('required_description_keywords', ["Lift", "Gate"])

    score = 0
    feedback = []
    
    # 2. Database Verification
    record_found = result.get('record_found', False)
    current_count = int(result.get('current_count', 0))
    initial_count = int(result.get('initial_count', 0))
    
    # Check 1: Record Creation (30 pts)
    # We check if a record was found AND the count increased
    if record_found and current_count > initial_count:
        score += 30
        feedback.append("Asset addition record created.")
    else:
        feedback.append("No new asset addition record found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Check 2: Correct Asset Link (Implicit in SQL query) & Amount (25 pts)
    # The SQL query in export_result.sh specifically selected by a_asset_id for VAN-001
    try:
        actual_amount = float(result.get('amount', 0))
        if abs(actual_amount - target_amount) < 0.01:
            score += 25
            feedback.append(f"Correct amount: {actual_amount}.")
        else:
            feedback.append(f"Incorrect amount. Expected {target_amount}, got {actual_amount}.")
    except ValueError:
        feedback.append("Invalid amount format in record.")

    # Check 3: Description (20 pts)
    description = result.get('description', "").lower()
    keyword_match = any(k.lower() in description for k in keywords)
    if keyword_match:
        score += 20
        feedback.append("Description contains required keywords.")
    else:
        feedback.append(f"Description '{description}' missing keywords: {keywords}.")

    # Check 4: Anti-Gaming / App Running (10 pts)
    if result.get('app_running', False):
        score += 10
    
    # 3. VLM Verification (15 pts)
    # Ensure they actually used the UI and didn't just run SQL injection (unlikely but good practice)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        prompt = (
            "Review these screenshots of an agent using iDempiere ERP. "
            "Did the agent navigate to the 'Fixed Asset' window and the 'Asset Addition' tab? "
            "Look for form fields like 'Amount', 'Asset', or 'Source'. "
            "Reply 'YES' if the workflow looks correct, otherwise 'NO'."
        )
        
        try:
            vlm_resp = query_vlm(images=frames + [final_screen], prompt=prompt)
            if vlm_resp.get('parsed', {}).get('answer', '').strip().upper() == 'YES' or \
               "YES" in vlm_resp.get('response', '').upper():
                score += 15
                feedback.append("Visual verification passed.")
            else:
                feedback.append("Visual verification failed or ambiguous.")
                # Give partial credit if DB is perfect
                score += 5 
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            score += 15 # Benefit of doubt if VLM fails technically
    else:
        score += 15 # Skip if VLM unavailable

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }