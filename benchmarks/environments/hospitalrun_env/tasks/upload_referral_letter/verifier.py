#!/usr/bin/env python3
"""
Verifier for upload_referral_letter task.

Verification Strategy:
1. Check CouchDB document for 'Hiroshi Tanaka' (patient_p1_00555).
2. Verify that the `_attachments` field exists.
3. Verify that an attachment named 'referral_letter.pdf' exists.
4. Verify the attachment content type is 'application/pdf'.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_upload_referral_letter(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. App Running Check (10 pts)
    if result.get("app_was_running"):
        score += 10
        feedback_parts.append("Browser was running.")
    else:
        feedback_parts.append("Browser was closed.")

    # 2. Patient Document Analysis
    patient_doc = result.get("patient_doc", {})
    
    # Check if doc exists (CouchDB returns 'error': 'not_found' if missing)
    if "error" in patient_doc and patient_doc["error"] == "not_found":
        return {
            "passed": False,
            "score": score,
            "feedback": "Patient record 'Hiroshi Tanaka' was not found in the database. " + " | ".join(feedback_parts)
        }
    
    # Check for attachments
    attachments = patient_doc.get("_attachments", {})
    if not attachments:
        feedback_parts.append("No files attached to patient record.")
    else:
        feedback_parts.append(f"Found {len(attachments)} attachment(s).")
        
        # Check specific file
        target_filename = "referral_letter.pdf"
        found = False
        correct_type = False
        
        # Iterate keys because sometimes systems prefix names
        for filename, meta in attachments.items():
            if target_filename in filename:
                found = True
                score += 70 # Major points for successful upload
                
                mime = meta.get("content_type", "")
                if mime == "application/pdf":
                    correct_type = True
                    score += 20
                else:
                    feedback_parts.append(f"Incorrect MIME type: {mime}")
                break
        
        if found:
            feedback_parts.append(f"File '{target_filename}' found in record.")
            if correct_type:
                feedback_parts.append("Correct PDF MIME type.")
        else:
            feedback_parts.append(f"File '{target_filename}' NOT found in attachments. Found: {list(attachments.keys())}")

    # Final Evaluation
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }