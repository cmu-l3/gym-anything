#!/usr/bin/env python3
"""
Verifier for record_supplier_payment task in Manager.io.
"""

import json
import tempfile
import os
import logging
import datetime

# Import VLM utils provided by framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for testing environment
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_supplier_payment(traj, env_info, task_info):
    """
    Verify that the supplier payment was recorded correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_amount = metadata.get('expected_amount', 2750.00)
    expected_payee = metadata.get('expected_payee', "Exotic Liquids")
    expected_date = metadata.get('expected_date', "2024-01-20")

    # 1. Load JSON Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Programmatic Verification (85 points)
    
    payment_found = result.get("payment_found", False)
    details = result.get("details", {})
    
    if payment_found:
        score += 20
        feedback_parts.append("Payment record found")
        
        # Payee Check (15 pts)
        payee = details.get("payee", "")
        if expected_payee.lower() in payee.lower():
            score += 15
            feedback_parts.append(f"Correct payee ({payee})")
        else:
            feedback_parts.append(f"Incorrect payee: expected '{expected_payee}', got '{payee}'")
            
        # Amount Check (15 pts)
        amount = details.get("amount", 0)
        if abs(amount - expected_amount) < 0.01:
            score += 15
            feedback_parts.append(f"Correct amount ({amount})")
        else:
            feedback_parts.append(f"Incorrect amount: expected {expected_amount}, got {amount}")
            
        # Date Check (10 pts)
        date_str = details.get("date", "")
        # Normalize date check (simple string presence often enough for scraping)
        if "2024" in date_str and ("01" in date_str or "Jan" in date_str) and "20" in date_str:
            score += 10
            feedback_parts.append(f"Correct date ({date_str})")
        else:
            feedback_parts.append(f"Date check failed: expected {expected_date}, got '{date_str}'")
            
        # Bank Account Check (10 pts)
        bank = details.get("bank_account", "")
        if "Cash on Hand" in bank:
            score += 10
            feedback_parts.append("Correct bank account")
        else:
            feedback_parts.append(f"Incorrect bank account: '{bank}'")
            
        # Description Check (10 pts)
        desc = details.get("description", "")
        if "beverage" in desc.lower():
            score += 10
            feedback_parts.append("Description correct")
        else:
            feedback_parts.append("Description missing or incorrect")
            
        # Line Account Check (5 pts)
        line = details.get("line_account", "")
        if "Accounts payable" in line:
            score += 5
            feedback_parts.append("Line account correct")
        else:
            feedback_parts.append("Line account incorrect (should be Accounts payable)")
            
    else:
        feedback_parts.append("No payment matching criteria found")

    # 3. VLM Verification (15 points)
    # Use trajectory frames to confirm interaction
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        You are verifying an agent using accounting software.
        Look at these screenshots. Did the agent:
        1. Open a "New Payment" or "Payment" form?
        2. Fill in "Exotic Liquids" as payee?
        3. Enter "2750" as the amount?
        
        Answer JSON: {"form_opened": bool, "details_entered": bool}
        """
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("form_opened"):
                score += 10
                feedback_parts.append("VLM: Form interaction confirmed")
            if parsed.get("details_entered"):
                score += 5
                feedback_parts.append("VLM: Details confirmed")
        else:
            # Fallback if VLM fails but programmatic passed
            if score >= 85:
                score += 15
                feedback_parts.append("VLM skipped (high confidence programmatic pass)")

    passed = score >= 60 and payment_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }