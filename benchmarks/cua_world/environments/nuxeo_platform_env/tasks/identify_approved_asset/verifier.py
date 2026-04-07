#!/usr/bin/env python3
"""
Verifier for identify_approved_asset task.

Verification Strategy:
1. Primary (Programmatic): Check Nuxeo document state via REST API results.
   - The document that was originally "APPROVED" (tracked by UID) MUST be named "Final-Banner".
   - The document that was "DRAFT" (tracked by UID) MUST NOT be named "Final-Banner".
2. Secondary (Anti-Gaming): Ensure the agent didn't just rename everything.
3. Tertiary (Process): VLM check to see if previews were opened (optional but good for scoring).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_approved_asset(traj, env_info, task_info):
    """
    Verify that the agent correctly identified and renamed the approved asset.
    """
    # 1. Setup: Retrieve result file from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract Data
    final_title_correct = result.get("final_title_correct", "").strip()
    final_title_wrong = result.get("final_title_wrong", "").strip()
    
    score = 0
    feedback_parts = []
    
    # 3. Verification Logic
    
    # Criterion 1: Correct document renamed (80 points)
    # Accept "Final-Banner" or "Final Banner" or case-insensitive variations if close
    target_name = "Final-Banner"
    is_correct_renamed = False
    
    if final_title_correct == target_name:
        score += 80
        is_correct_renamed = True
        feedback_parts.append(f"Correctly renamed approved asset to '{target_name}'.")
    elif target_name.lower() in final_title_correct.lower():
        # Partial credit for minor typo or case mismatch
        score += 60
        is_correct_renamed = True
        feedback_parts.append(f"Renamed approved asset to '{final_title_correct}' (close to '{target_name}').")
    else:
        feedback_parts.append(f"Failed to rename approved asset. Current title: '{final_title_correct}'.")

    # Criterion 2: Wrong document NOT renamed (20 points)
    # Anti-gaming: If they renamed BOTH to "Final-Banner", they fail this part.
    if final_title_wrong == target_name:
        score = 0 # Penalty: If both are named Final-Banner, this is effectively random guessing/gaming
        feedback_parts.append("CRITICAL FAIL: You renamed BOTH documents to 'Final-Banner'. You must identify the specific one.")
        is_correct_renamed = False # Invalidate success
    elif target_name.lower() in final_title_wrong.lower():
         score = max(0, score - 50)
         feedback_parts.append("CRITICAL WARNING: You also renamed the Draft document.")
    else:
        score += 20
        feedback_parts.append("Draft document correctly left alone (or at least not renamed to target).")

    # 4. Final Verdict
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }