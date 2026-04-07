#!/usr/bin/env python3
"""
Verifier for Distraction-Free Invoice Archival task.

Criteria:
1. PDF Created (10 pts): File exists at correct path and was created during task.
2. Content Integrity (30 pts): "Invoice #8492" and "1,240.50" are present.
3. Cleanliness (60 pts):
    - No "FLASH SALE" (20 pts)
    - No "Chat with Agent" (20 pts)
    - No "We use cookies" (20 pts)

Pass Threshold: 80 points.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_distraction_free_invoice_archival(traj, env_info, task_info):
    """
    Verify the agent cleaned up the invoice before saving.
    """
    # 1. Setup and load result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract Data
    pdf_exists = result.get("pdf_exists", False)
    pdf_modified = result.get("pdf_modified_after_start", False)
    content = result.get("pdf_content", "")
    
    score = 0
    feedback_parts = []
    
    # 3. Scoring Logic
    
    # CRITERION 1: File Creation (10 pts)
    if pdf_exists and pdf_modified:
        score += 10
        feedback_parts.append("PDF saved successfully.")
    elif pdf_exists:
        feedback_parts.append("PDF exists but timestamp indicates it is old.")
    else:
        feedback_parts.append("PDF file not found at expected location.")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }

    # CRITERION 2: Content Integrity (30 pts)
    # Must contain essential invoice data
    required_phrases = ["Invoice #8492", "1,240.50"]
    missing_required = [p for p in required_phrases if p not in content]
    
    if not missing_required:
        score += 30
        feedback_parts.append("Invoice content intact.")
    else:
        feedback_parts.append(f"Missing invoice details: {', '.join(missing_required)}.")

    # CRITERION 3: Cleanliness / Distraction Removal (60 pts)
    distractions = {
        "FLASH SALE": "Marketing Banner",
        "Chat with Agent": "Chat Widget",
        "We use cookies": "Cookie Footer"
    }
    
    clean_score = 0
    for text, name in distractions.items():
        if text not in content:
            clean_score += 20
            feedback_parts.append(f"{name} removed.")
        else:
            feedback_parts.append(f"{name} DETECTED (failed to remove).")
            
    score += clean_score

    # 4. Final Verdict
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }