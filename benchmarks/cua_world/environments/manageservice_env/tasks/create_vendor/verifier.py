#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_vendor(traj, env_info, task_info):
    """
    Verifies that the vendor was created with correct details.
    Uses Database verification (primary) and VLM (secondary).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []
    
    # 1. Database Verification (Primary)
    vendor_exists = result.get('vendor_exists', False)
    vendor_data = result.get('vendor_data', {})
    
    # Normalize keys to lowercase for easier matching (Postgres returns usually lowercase)
    data = {k.lower(): str(v).lower() for k, v in vendor_data.items()}
    
    if vendor_exists:
        score += 25
        feedback_parts.append("Vendor record created.")
        
        # Check specific fields (fuzzy matching due to potential schema diffs)
        # Name
        if "proav" in data.get('vendorname', ''):
            score += 5
        
        # Contact Person (check various potential column names)
        contact = data.get('contactperson', '') or data.get('contact_person', '') or data.get('contactname', '')
        if "rachel" in contact or "dominguez" in contact:
            score += 10
            feedback_parts.append("Contact person correct.")
        else:
            feedback_parts.append(f"Contact person incorrect/missing (found: {contact}).")
            
        # Email
        email = data.get('email', '') or data.get('emailid', '') or data.get('email_addr', '')
        if "rdominguez@proavdist.com" in email:
            score += 10
            feedback_parts.append("Email correct.")
        else:
            feedback_parts.append(f"Email incorrect (found: {email}).")
            
        # Phone
        phone = data.get('phone', '') or data.get('phoneno', '')
        if "512-555-0147" in phone:
            score += 10
            feedback_parts.append("Phone correct.")
        else:
            feedback_parts.append("Phone incorrect.")

        # Address/City/Zip
        addr_full = str(data) # naive search in all fields if specific cols fail
        if "austin" in addr_full:
            score += 5
        if "78757" in addr_full:
            score += 5
        if "shoal creek" in addr_full:
            score += 5
            
    else:
        feedback_parts.append("Vendor record NOT found in database.")

    # 2. VLM Verification (Secondary)
    # Check if agent navigated to Purchases/Vendors and filled a form
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of ManageEngine ServiceDesk Plus.
    Did the user:
    1. Navigate to the 'Purchases' or 'Vendors' section?
    2. Fill out a 'New Vendor' form?
    3. Enter details for 'ProAV Distribution'?
    
    Reply with JSON: {"navigated_purchases": bool, "filled_form": bool, "correct_details_visible": bool}
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt).get('parsed', {})
        
        if vlm_res.get('navigated_purchases', False):
            score += 10
            feedback_parts.append("VLM: Purchases module visited.")
        if vlm_res.get('filled_form', False):
            score += 10
            feedback_parts.append("VLM: Vendor form interaction detected.")
        if vlm_res.get('correct_details_visible', False):
            score += 5
            feedback_parts.append("VLM: 'ProAV' details visible.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Graceful degradation: if DB passed, we assume UI interaction happened
        if vendor_exists:
            score += 10 

    # Pass logic
    passed = (score >= 60) and vendor_exists
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }