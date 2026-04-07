#!/usr/bin/env python3
"""
Verifier for upload_scanned_document@1
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_upload_scanned_document(traj, env_info, task_info):
    """
    Verify that the document was uploaded to the correct patient with correct metadata.
    """
    # 1. Setup: Retrieve result data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    initial_count = int(result.get('initial_doc_count', 0))
    final_count = int(result.get('final_doc_count', 0))
    latest_doc = result.get('latest_document')
    target_pid = result.get('target_pid', 0)
    
    metadata = task_info.get('metadata', {})
    expected_keywords = metadata.get('expected_description_keywords', ['cardiology', 'consult'])
    
    score = 0
    feedback_parts = []
    passed = False

    # 3. Verification Logic

    # Criterion A: Document count increased (Anti-gaming / Basic success) (20 pts)
    if final_count > initial_count:
        score += 20
        feedback_parts.append("Document successfully added to patient record.")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new document found in patient record. Did you save the upload?"
        }

    # Criterion B: Latest document validation (80 pts total)
    if latest_doc and isinstance(latest_doc, dict):
        
        # 1. Check Description (Text metadata) (40 pts)
        desc = latest_doc.get('description', '').lower()
        keyword_hits = [k for k in expected_keywords if k in desc]
        
        if len(keyword_hits) == len(expected_keywords):
            score += 40
            feedback_parts.append(f"Description correct ('{latest_doc.get('description')}').")
        elif len(keyword_hits) > 0:
            score += 20
            feedback_parts.append(f"Description partially correct. Expected terms {expected_keywords}, found {keyword_hits}.")
        else:
            feedback_parts.append(f"Description missing required keywords. Got: '{latest_doc.get('description')}'.")

        # 2. Check File Association (Binary upload) (40 pts)
        # 'url' field in NOSH usually stores the filename or path. It should not be null/empty.
        doc_url = latest_doc.get('url', '')
        if doc_url and len(str(doc_url)) > 3:
            score += 40
            feedback_parts.append("File attachment verified in database.")
        else:
            feedback_parts.append("Record created but file attachment missing/empty.")
            
    else:
        feedback_parts.append("Could not retrieve document details.")

    # 4. Final Scoring
    if score >= 80:
        passed = True
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }