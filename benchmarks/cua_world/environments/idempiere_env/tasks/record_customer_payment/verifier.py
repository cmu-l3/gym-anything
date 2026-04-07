#!/usr/bin/env python3
"""
Verifier for record_customer_payment@1.

Verifies that the agent created a specific Payment record in iDempiere.
Criteria:
1. Payment record created (Anti-gaming: must be new)
2. Correct Business Partner (Joe Block)
3. Correct Amount (1750.00)
4. Correct Doc Type (AR Receipt)
5. Correct Tender Type (Check) & Check No
6. Document Status (Completed)
7. VLM verification of UI interaction
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_customer_payment(traj, env_info, task_info):
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "VLM query function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    target_bp = metadata.get('target_bp_name', "Joe Block")
    target_amt = float(metadata.get('target_amount', 1750.00))
    target_check = metadata.get('target_check_no', "20251547")
    target_status = metadata.get('target_doc_status', "CO") # CO = Completed

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # Programmatic Verification (90 points max)
    # ----------------------------------------------------------------
    
    payment_found = result.get('payment_found', False)
    details = result.get('payment_details', {})
    task_start = result.get('task_start', 0)

    if not payment_found:
        feedback_parts.append("❌ No new payment record found.")
    else:
        # Check 1: Record Exists & Anti-Gaming (Timestamp)
        created_ts = details.get('created_ts', 0)
        # Allow 5s buffer for clock skew, though usually perfectly synced in docker
        if created_ts >= (task_start - 5):
            score += 15
            feedback_parts.append("✅ New payment record created.")
        else:
            feedback_parts.append("⚠️ Payment record found but timestamp predates task (pre-existing?).")
            # We continue verifying but this is suspicious
        
        # Check 2: Business Partner (15 pts)
        actual_bp = details.get('bp_name', '')
        if target_bp.lower() in actual_bp.lower():
            score += 15
            feedback_parts.append(f"✅ Correct Business Partner ({actual_bp}).")
        else:
            feedback_parts.append(f"❌ Incorrect Business Partner. Expected '{target_bp}', got '{actual_bp}'.")

        # Check 3: Amount (15 pts)
        try:
            actual_amt = float(details.get('amount', 0))
            if abs(actual_amt - target_amt) < 0.01:
                score += 15
                feedback_parts.append(f"✅ Correct Amount ({target_amt}).")
            else:
                feedback_parts.append(f"❌ Incorrect Amount. Expected {target_amt}, got {actual_amt}.")
        except:
            feedback_parts.append("❌ Invalid amount format.")

        # Check 4: Is Receipt (10 pts)
        if details.get('is_receipt') == 'Y':
            score += 10
            feedback_parts.append("✅ Document is an AR Receipt.")
        else:
            feedback_parts.append("❌ Document is NOT a Receipt (likely AP Payment).")

        # Check 5: Tender Type & Check No (10 + 10 pts)
        if details.get('tender_type') == 'K': # K = Check in iDempiere
            score += 10
            feedback_parts.append("✅ Tender Type is Check.")
        else:
            feedback_parts.append(f"❌ Incorrect Tender Type. Expected Check (K), got '{details.get('tender_type')}'.")
        
        if str(details.get('check_no')) == str(target_check):
            score += 10
            feedback_parts.append(f"✅ Correct Check Number ({target_check}).")
        else:
            feedback_parts.append(f"❌ Incorrect Check Number. Expected {target_check}, got '{details.get('check_no')}'.")

        # Check 6: Document Status (15 pts)
        status = details.get('doc_status')
        if status == 'CO':
            score += 15
            feedback_parts.append("✅ Document is Completed/Posted.")
        elif status == 'DR':
            score += 5 # Partial credit for Draft
            feedback_parts.append("⚠️ Document is saved but still in Draft status (not Completed).")
        else:
            feedback_parts.append(f"❌ Document status is '{status}'.")

    # ----------------------------------------------------------------
    # VLM Verification (10 points max)
    # ----------------------------------------------------------------
    # Use trajectory to verify they actually used the Payment window
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        frames = [get_final_screenshot(traj)]
        
    vlm_prompt = """
    Review these screenshots of a user performing a task in iDempiere (ERP).
    The user should be entering a Payment/Receipt.
    
    Look for:
    1. The 'Payment' or 'Payment/Receipt' window.
    2. Fields like 'Business Partner', 'Payment Amount', 'Check No'.
    3. The user interacting with these fields.
    
    Did the user successfully navigate to the Payment window and interact with the form?
    Respond with JSON: {"success": true/false, "confidence": "high/medium/low"}
    """
    
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res.get("parsed", {}).get("success", False):
            score += 10
            feedback_parts.append("✅ VLM verified UI interaction.")
        else:
            feedback_parts.append("⚠️ VLM could not clearly verify UI interaction.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    # ----------------------------------------------------------------
    # Final Decision
    # ----------------------------------------------------------------
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }