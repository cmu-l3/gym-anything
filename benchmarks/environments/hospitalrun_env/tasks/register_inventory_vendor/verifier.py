#!/usr/bin/env python3
"""
Verifier for register_inventory_vendor task.
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_inventory_vendor(traj, env_info, task_info):
    """
    Verifies that the agent created the inventory vendor correctly.
    
    Criteria:
    1. Document exists in CouchDB (40 pts)
    2. Address matches (20 pts)
    3. Phone matches (20 pts)
    4. Account/Note matches (10 pts)
    5. VLM Verification (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('vendor_name', "Global Pharma Supplies")
    expected_address = metadata.get('vendor_address', "42 Logistics Blvd, Metro City, NY 10001")
    expected_phone = metadata.get('vendor_phone', "555-0199")
    expected_note = metadata.get('vendor_account_note', "GPS-2026-X")

    # Retrieve result JSON
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
    feedback_parts = []
    
    # 1. Check Document Existence
    found = result.get("found", False)
    docs = result.get("documents", [])
    
    if not found or not docs:
        feedback_parts.append(f"Vendor '{expected_name}' not found in database.")
        # Fail early if not found
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    
    score += 40
    feedback_parts.append("Vendor created")
    
    # Use the first matching document
    vendor = docs[0]
    
    # 2. Verify Address
    # HospitalRun address might be a string or object
    addr_val = vendor.get("address", "")
    if isinstance(addr_val, dict):
        addr_val = " ".join([str(v) for v in addr_val.values()])
    
    # Flexible check for key parts of address
    if "42 Logistics" in str(addr_val) and "Metro City" in str(addr_val):
        score += 20
        feedback_parts.append("Address correct")
    else:
        feedback_parts.append(f"Address mismatch (got '{addr_val}')")
        
    # 3. Verify Phone
    phone_val = vendor.get("phone", "")
    if expected_phone in str(phone_val):
        score += 20
        feedback_parts.append("Phone correct")
    else:
        feedback_parts.append(f"Phone mismatch (got '{phone_val}')")
        
    # 4. Verify Account Note
    # Check multiple fields since user might put it in Description, Note, or Account Number
    note_found = False
    for field in ["accountNumber", "note", "notes", "description"]:
        val = vendor.get(field, "")
        if expected_note in str(val):
            note_found = True
            break
            
    if note_found:
        score += 10
        feedback_parts.append("Account/Note correct")
    else:
        feedback_parts.append(f"Account number '{expected_note}' not found in relevant fields")

    # 5. VLM Verification (Trajectory Check)
    # Ensure they actually used the UI
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = (
            "Review these screenshots of a user using HospitalRun software. "
            "Does the user navigate to the 'Inventory' or 'Suppliers' section? "
            "Do you see a form being filled out with 'Global Pharma Supplies'? "
            "Return JSON: {\"ui_interaction\": true, \"form_filled\": true}"
        )
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_res and vlm_res.get("parsed", {}).get("form_filled"):
            score += 10
            feedback_parts.append("VLM verified UI interaction")
        else:
            feedback_parts.append("VLM could not confirm form filling")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Be lenient if VLM fails technically, assign points if DB record is perfect
        if score >= 90:
            score += 10

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }