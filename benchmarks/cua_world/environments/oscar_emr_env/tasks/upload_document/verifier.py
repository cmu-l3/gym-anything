#!/usr/bin/env python3
"""
Verifier for upload_document task in OSCAR EMR.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_upload_document(traj, env_info, task_info):
    """
    Verify that the document was uploaded to the correct patient with correct metadata.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_keywords = metadata.get('expected_keywords', ["Cardiology", "Consult", "Patel"])
    
    # Copy result JSON
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
    
    # 1. Document Record Exists and Linked to Patient (50 pts)
    doc_found = result.get('document_found', False)
    is_new = result.get('is_newly_created', False)
    
    if doc_found and is_new:
        score += 50
        feedback_parts.append("New document record created and linked to patient")
    elif doc_found:
        score += 25
        feedback_parts.append("Document record found, but may pre-date task start (partial credit)")
    else:
        feedback_parts.append("No document record found for patient")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Get details
    details = result.get('document_details', {})
    desc = details.get('description', '')
    dtype = details.get('type', '')
    
    # 2. Description Verification (20 pts)
    # Check for keywords
    matched_keywords = [kw for kw in expected_keywords if kw.lower() in desc.lower()]
    if len(matched_keywords) >= 2:
        score += 20
        feedback_parts.append(f"Description correct (keywords: {matched_keywords})")
    elif len(matched_keywords) == 1:
        score += 10
        feedback_parts.append(f"Description partially correct (found: {matched_keywords})")
    else:
        feedback_parts.append(f"Description missing keywords (got: '{desc}')")

    # 3. Document Type Set (15 pts)
    # Just check if it's not empty/default
    if dtype and dtype.lower() not in ['unknown', '']:
        score += 15
        feedback_parts.append(f"Document type set to '{dtype}'")
    else:
        feedback_parts.append("Document type not set")

    # 4. File Storage Check (15 pts)
    if result.get('file_exists_storage', False):
        score += 15
        feedback_parts.append("Uploaded file confirmed on server storage")
    else:
        feedback_parts.append("Warning: Physical file not found on server storage (upload might have failed)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }