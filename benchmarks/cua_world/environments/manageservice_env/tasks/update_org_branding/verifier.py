#!/usr/bin/env python3
import json
import os
import logging
import tempfile
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_org_branding(traj, env_info, task_info):
    """
    Verify that organization details and logo were updated.
    
    Scoring:
    - Organization Name "Initrode Global": 30 pts
    - Address contains "Austin" or "Freidrich": 20 pts
    - Email/Phone match: 20 pts
    - Logo updated (File found OR DB confirms OR VLM confirms): 30 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    score = 0
    feedback = []
    
    # Parse DB record (Raw string from pipe-separated or similar psql output)
    # The export script used 'psql -A -t' style implies pipe separated if not specified, 
    # but sdp_db_exec uses -A -t which is pipe separated by default.
    db_raw = result.get("db_record_raw", "")
    
    # Expected values
    exp_name = "Initrode Global"
    exp_email = "support@initrode.com"
    exp_phone = "512-555-0199"
    
    # 1. Verify Name (30 pts)
    if exp_name.lower() in db_raw.lower():
        score += 30
        feedback.append("Organization Name updated correctly.")
    else:
        feedback.append(f"Organization Name mismatch (DB: {db_raw})")

    # 2. Verify Address (20 pts)
    if "austin" in db_raw.lower() or "freidrich" in db_raw.lower() or "78744" in db_raw:
        score += 20
        feedback.append("Address updated correctly.")
    else:
        feedback.append("Address not updated.")

    # 3. Verify Contact Info (20 pts)
    contact_score = 0
    if exp_email.lower() in db_raw.lower():
        contact_score += 10
    if exp_phone in db_raw:
        contact_score += 10
    
    if contact_score == 20:
        feedback.append("Contact info updated correctly.")
    elif contact_score > 0:
        feedback.append("Partial contact info update.")
    else:
        feedback.append("Contact info not updated.")
    
    score += contact_score

    # 4. Verify Logo (30 pts)
    # Strategy: File check -> DB check -> VLM check
    logo_score = 0
    
    # A. File check
    if result.get("new_logo_file_found", False):
        logo_score = 30
        feedback.append("New logo file detected.")
    
    # B. DB Check (if file check failed)
    elif "initrode" in db_raw.lower() and ("png" in db_raw.lower() or "jpg" in db_raw.lower()):
        # Sometimes the filename is stored in DB
        logo_score = 30
        feedback.append("Logo reference found in database.")
        
    # C. VLM Check (if programmatic checks fail)
    else:
        logger.info("Falling back to VLM for logo verification")
        final_img = get_final_screenshot(traj)
        if final_img:
            vlm_resp = query_vlm(
                image=final_img,
                prompt="Look at the screen. Does the ServiceDesk Plus interface show a logo that says 'Initrode' or 'Initrode Global' in the header or organization details page? Answer 'yes' or 'no'."
            )
            if vlm_resp and vlm_resp.get("parsed", {}).get("answer", "").lower() == "yes":
                logo_score = 30
                feedback.append("VLM confirmed logo update.")
            else:
                feedback.append("Logo update not detected.")
    
    score += logo_score

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }