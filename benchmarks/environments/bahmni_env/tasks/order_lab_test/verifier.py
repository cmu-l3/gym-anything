#!/usr/bin/env python3
"""
Verifier for order_lab_test@1.

Verifies that the agent successfully ordered specific lab tests for the correct patient.
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_order_lab_test(traj, env_info, task_info):
    """
    Verify lab test ordering.
    
    Criteria:
    1. At least 2 new test orders created for the patient (20 pts)
    2. 'Haemoglobin' ordered (35 pts)
    3. 'ESR' / 'Erythrocyte Sedimentation Rate' ordered (35 pts)
    4. VLM visual confirmation of workflow (10 pts)
    
    Pass threshold: 80 points.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}
        
    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Check for script errors
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # 1. Check Order Count
    new_count = result.get("new_order_count", 0)
    if new_count >= 2:
        score += 20
        feedback_parts.append("✅ Created new lab orders")
    elif new_count > 0:
        score += 10
        feedback_parts.append("⚠️ Created fewer orders than expected")
    else:
        feedback_parts.append("❌ No new orders found")
        
    # 2. Check Haemoglobin
    if result.get("found_haemoglobin"):
        score += 35
        feedback_parts.append("✅ Haemoglobin ordered")
    else:
        feedback_parts.append("❌ Haemoglobin missing")
        
    # 3. Check ESR
    if result.get("found_esr"):
        score += 35
        feedback_parts.append("✅ ESR ordered")
    else:
        feedback_parts.append("❌ ESR missing")
        
    # 4. VLM Verification (Visual Check)
    # We check if the agent actually navigated the clinical interface
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_ss = get_final_screenshot(traj)
        
        prompt = """
        Review this sequence of screenshots from a hospital software (Bahmni).
        The user goal is to order lab tests.
        
        Look for:
        1. Navigation to the 'Orders' or 'Lab Orders' tab.
        2. Selection of tests like 'Haemoglobin' or 'ESR'.
        3. A successful save action (or updated dashboard showing orders).
        
        Does the visual evidence support that lab orders were placed?
        Answer 'YES' or 'NO' with brief reasoning.
        """
        
        try:
            # We use the frames + final screenshot
            vlm_resp = query_vlm(images=frames + [final_ss], prompt=prompt)
            if vlm_resp and vlm_resp.get("parsed", {}).get("answer", "").upper() == "YES":
                vlm_score = 10
                feedback_parts.append("✅ Visual confirmation of ordering workflow")
            elif "YES" in str(vlm_resp).upper(): # Fallback if parsing fails
                vlm_score = 10
                feedback_parts.append("✅ Visual confirmation (text match)")
            else:
                feedback_parts.append("⚠️ VLM could not visually confirm workflow")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # If programmatic check passed perfectly, give benefit of doubt for VLM
            if score >= 90:
                vlm_score = 10
    else:
        # If no VLM available, give points if programmatic passed
        if score >= 90:
            vlm_score = 10
            
    score += vlm_score

    # Final verdict
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }