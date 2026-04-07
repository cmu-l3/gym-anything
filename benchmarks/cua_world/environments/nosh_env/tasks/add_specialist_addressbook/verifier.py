#!/usr/bin/env python3
"""
Verifier for add_specialist_addressbook task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_specialist(traj, env_info, task_info):
    """
    Verify that the specialist was added to the addressbook with correct details.
    
    Scoring Breakdown (100 pts):
    - 20 pts: Database record exists (Basic success)
    - 15 pts: Correct Name (First/Last/Display)
    - 15 pts: Correct Specialty (Cardiology)
    - 15 pts: Correct NPI (1477658923)
    - 10 pts: Correct Contact Info (Phone/Fax/Email)
    - 10 pts: Correct Address (Street/City/State/Zip)
    - 15 pts: Anti-gaming (Count increased from initial)
    
    Pass Threshold: 60 pts AND Record Must Exist
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
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
    
    # 2. Check Database Record (Primary Verification)
    entry_found = result.get('entry_found', False)
    entry_data = result.get('entry_data') or {}
    
    if not entry_found:
        feedback.append("FAIL: No addressbook entry found for 'Torres'.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}
    
    score += 20
    feedback.append("SUCCESS: Addressbook entry created (+20).")
    
    # Verify Fields
    # Metadata targets
    meta = task_info.get('metadata', {})
    
    # Name Check
    lname = entry_data.get('lastname', '')
    fname = entry_data.get('firstname', '')
    dname = entry_data.get('displayname', '')
    if meta.get('target_lastname', 'Torres') in lname and meta.get('target_firstname', 'Rebecca') in fname:
        score += 15
        feedback.append("Name matches (+15).")
    else:
        feedback.append(f"Name mismatch: Found {fname} {lname}.")

    # Specialty Check
    spec = entry_data.get('specialty', '')
    if meta.get('target_specialty', 'Cardiology').lower() in spec.lower():
        score += 15
        feedback.append("Specialty matches (+15).")
    else:
        feedback.append(f"Specialty mismatch: Found '{spec}'.")

    # NPI Check
    npi = str(entry_data.get('npi', ''))
    if meta.get('target_npi', '1477658923') in npi:
        score += 15
        feedback.append("NPI matches (+15).")
    else:
        feedback.append(f"NPI mismatch: Found '{npi}'.")

    # Contact Info Check (Phone OR Email OR Fax - permissive)
    phone = str(entry_data.get('phone', ''))
    email = str(entry_data.get('email', ''))
    if meta.get('target_phone', '555') in phone or 'rtorres' in email:
        score += 10
        feedback.append("Contact info matches (+10).")
    else:
        feedback.append("Contact info incorrect/missing.")

    # Address Check
    city = entry_data.get('city', '')
    state = entry_data.get('state', '')
    street = entry_data.get('street_address1', '')
    if 'Springfield' in city and 'MA' in state and '450' in street:
        score += 10
        feedback.append("Address matches (+10).")
    else:
        feedback.append("Address incorrect/missing.")

    # 3. Anti-Gaming / Count Check
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    
    if current_count > initial_count:
        score += 15
        feedback.append("Database count increased (+15).")
    else:
        feedback.append("WARNING: Database count did not increase (modified existing?).")
        # We don't fail, but we don't give the bonus points

    # 4. VLM Trajectory Verification (Optional bonus or confirmation)
    # If score is borderline, VLM can confirm UI interaction
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    if final_img:
        frames.append(final_img)
    
    # We won't use VLM to add points, just to log for debugging or break ties if needed.
    # For now, purely programmatic scoring is robust enough.

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }