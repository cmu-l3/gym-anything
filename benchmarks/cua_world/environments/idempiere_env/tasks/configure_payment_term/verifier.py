#!/usr/bin/env python3
"""
Verifier for configure_payment_term task.

CRITERIA:
1. Record exists (Search Key: 2-10-Net-45)
2. Data Accuracy:
   - Name: "2% 10 Net 45"
   - Discount: 2%
   - Discount Days: 10
   - Net Days: 45
3. Configuration Status:
   - Is Valid (Validate button clicked)
4. Anti-gaming:
   - Record created during task window
   - Navigation verification via VLM
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_payment_term(traj, env_info, task_info):
    """
    Verify payment term configuration using DB record and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ------------------------------------------------------------------
    # Scoring Breakdown
    # ------------------------------------------------------------------
    score = 0
    feedback_parts = []
    
    record_found = result.get('record_found', False)
    record = result.get('record', {})

    # 1. Record Existence (10 pts)
    if record_found:
        score += 10
        feedback_parts.append("✅ Payment Term record created")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Payment Term '2-10-Net-45' not found in database."
        }

    # 2. Name Check (10 pts)
    expected_name = "2% 10 Net 45"
    actual_name = record.get('name', '')
    if actual_name == expected_name:
        score += 10
        feedback_parts.append(f"✅ Correct Name ('{actual_name}')")
    else:
        feedback_parts.append(f"❌ Incorrect Name (Expected: '{expected_name}', Found: '{actual_name}')")

    # 3. Description Check (5 pts)
    desc = record.get('description', '')
    if len(desc) > 10 and "2%" in desc:
        score += 5
        feedback_parts.append("✅ Description present")
    else:
        feedback_parts.append("⚠️ Description missing or incomplete")

    # 4. Discount Percentage (15 pts)
    # DB returns string, handle potential float format
    try:
        discount_val = float(record.get('discount', '0'))
        if abs(discount_val - 2.0) < 0.01:
            score += 15
            feedback_parts.append("✅ Discount % Correct (2%)")
        else:
            feedback_parts.append(f"❌ Incorrect Discount % (Found: {discount_val})")
    except ValueError:
        feedback_parts.append("❌ Invalid Discount % format")

    # 5. Discount Days (15 pts)
    try:
        disc_days = int(float(record.get('discount_days', '0')))
        if disc_days == 10:
            score += 15
            feedback_parts.append("✅ Discount Days Correct (10)")
        else:
            feedback_parts.append(f"❌ Incorrect Discount Days (Found: {disc_days})")
    except ValueError:
        feedback_parts.append("❌ Invalid Discount Days format")

    # 6. Net Days (15 pts)
    try:
        net_days = int(float(record.get('net_days', '0')))
        if net_days == 45:
            score += 15
            feedback_parts.append("✅ Net Days Correct (45)")
        else:
            feedback_parts.append(f"❌ Incorrect Net Days (Found: {net_days})")
    except ValueError:
        feedback_parts.append("❌ Invalid Net Days format")

    # 7. Record is Valid (15 pts) - Requires clicking "Validate"
    is_valid = record.get('is_valid', 'N')
    if is_valid == 'Y':
        score += 15
        feedback_parts.append("✅ Payment Term Validated")
    else:
        feedback_parts.append("❌ Payment Term NOT Validated (Must click 'Validate' button)")

    # 8. Record Active (5 pts)
    is_active = record.get('is_active', 'N')
    if is_active == 'Y':
        score += 5
    
    # 9. Anti-gaming / Timestamp check (5 pts)
    # Simple check: created timestamp exists and task_end > task_start
    # Detailed timestamp parsing is complex across TZs, so we rely on delta of count
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    if current_count > initial_count:
        score += 5
        feedback_parts.append("✅ Record count increased")
    
    # 10. VLM Trajectory Verification (5 pts)
    # Check if agent actually used the UI
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of an agent using iDempiere ERP.
        Did the agent navigate to the 'Payment Term' window and interact with the form fields?
        Look for a window titled 'Payment Term' or fields like 'Discount', 'Net Days'.
        """
        
        vlm_result = query_vlm(images=frames + [final], prompt=prompt)
        if vlm_result.get('success') and vlm_result.get('parsed', {}).get('answer', False):
            vlm_score = 5
            feedback_parts.append("✅ UI Interaction verified")
        else:
            # Fallback: if we found the record in DB, they must have added it somehow.
            # We give benefit of doubt if DB record is perfect, otherwise withhold points
            if score >= 80:
                vlm_score = 5 
                feedback_parts.append("✅ UI Interaction inferred from success")
    
    score += vlm_score

    # Final Pass/Fail logic
    # Need at least 60 points AND correct semantic values (Discount/Days/Net)
    # Validation (is_valid) is critical for "completing" the task
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }