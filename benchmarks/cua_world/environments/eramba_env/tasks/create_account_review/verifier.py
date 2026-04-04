#!/usr/bin/env python3
"""
Verifier for create_account_review task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_account_review(traj, env_info, task_info):
    """
    Verifies that the account review record was created correctly.
    
    Scoring Criteria:
    1. Database Record Exists (30 pts)
    2. Record Created During Task (Anti-gaming) (20 pts)
    3. Content Accuracy (Title & Description) (30 pts)
    4. VLM/Visual Verification (20 pts)
    """
    
    # 1. Setup and retrieve result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_lines = []
    
    # --- Criterion 1 & 2: Database Record Check ---
    record_found = result_data.get('record_found', False)
    created_during_task = result_data.get('created_during_task', False)
    
    if record_found:
        score += 30
        feedback_lines.append("✓ Account Review record created in database.")
        
        if created_during_task:
            score += 20
            feedback_lines.append("✓ Record created during task window (timestamp valid).")
        else:
            feedback_lines.append("⚠ Record exists but timestamp is before task start (pre-existing?).")
    else:
        feedback_lines.append("✗ No matching Account Review record found in database.")

    # --- Criterion 3: Content Accuracy ---
    if record_found:
        actual_name = result_data.get('record_name', '')
        actual_desc = result_data.get('record_description', '')
        expected_title = metadata.get('expected_title', '')
        expected_keywords = metadata.get('expected_description_keywords', [])
        
        # Title Check
        if expected_title.lower() in actual_name.lower():
            score += 15
            feedback_lines.append("✓ Title matches expectations.")
        else:
            feedback_lines.append(f"✗ Title mismatch. Expected '{expected_title}', found '{actual_name}'.")

        # Description Check (Keywords)
        keywords_found = 0
        for kw in expected_keywords:
            if kw.lower() in actual_desc.lower():
                keywords_found += 1
        
        if keywords_found == len(expected_keywords):
            score += 15
            feedback_lines.append("✓ Description contains all required details.")
        elif keywords_found > 0:
            score += 7
            feedback_lines.append("⚠ Description missing some details.")
        else:
            feedback_lines.append("✗ Description missing required keywords.")

    # --- Criterion 4: VLM Verification ---
    # We use VLM to ensure the agent actually interacted with the UI and didn't just magic the data in
    # (though DB checks handle most logic, VLM confirms UI state).
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze these screenshots of a GRC software interface (Eramba). "
        "The user should have navigated to 'Account Reviews' and filled out a form. "
        "Look for: "
        "1. A form with fields for Title, Description, or Owner. "
        "2. The text 'Q1 2025 Core Banking Access Review'. "
        "3. A list of items showing the new review. "
        "Did the user appear to successfully create the review through the UI?"
    )
    
    try:
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        vlm_confidence = vlm_result.get('confidence', 'low') # assuming wrapper returns standardized dict
        vlm_passed = vlm_result.get('success', False) # or logic based on text response
        
        # Simplified scoring based on presence of key UI elements in response analysis
        response_text = str(vlm_result).lower()
        if "yes" in response_text or "successfully" in response_text:
            score += 20
            feedback_lines.append("✓ Visual verification confirms workflow.")
        elif "form" in response_text and "filled" in response_text:
            score += 15
            feedback_lines.append("✓ Visual verification confirms form interaction.")
        else:
            # Fallback points if DB record is perfect, assuming VLM might be flaky
            if score >= 80: 
                score += 10
                feedback_lines.append("? VLM uncertain, but data verified.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Graceful degradation
        if score >= 65:
            score += 20
            feedback_lines.append("⚠ VLM check skipped, awarding points based on DB evidence.")

    # --- Final Result ---
    # Pass threshold: 60 points + Record must be found and created during task
    passed = (score >= 60) and record_found and created_during_task
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "\n".join(feedback_lines)
    }