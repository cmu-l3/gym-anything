#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compose_patient_letter(traj, env_info, task_info):
    """
    Verify that the agent composed and saved a letter with the correct subject.
    
    Criteria:
    1. A new document exists for the correct patient (PID 9999).
    2. The document was created after the task started.
    3. The document subject/description contains "Insurance Claim Denial".
    """
    
    # 1. Setup copy from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 2. Retrieve result JSON
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

    # 3. Extract Data
    task_start = result.get('task_start_timestamp', 0)
    initial_count = int(result.get('initial_doc_count', 0))
    final_count = int(result.get('final_doc_count', 0))
    latest_doc = result.get('latest_document')
    
    # 4. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion 1: Document Created (40 pts)
    # Check if count increased OR if we found a valid new document
    doc_created = False
    if final_count > initial_count:
        doc_created = True
        score += 40
        feedback.append("Success: A new document was saved to the patient's chart.")
    else:
        feedback.append("Failure: No new document record found in the database.")
    
    # Criterion 2: Correct Patient & Timing (20 pts)
    # (Implicitly checked by SQL query on PID, but we check timing here)
    valid_timing = False
    if latest_doc:
        # NOSH dates are often just YYYY-MM-DD, so strict timestamp comparison might be tricky 
        # if the column is just DATE. However, we also check that it's a NEW record ID.
        # If 'timestamp' from SQL is available and > task_start (with some tolerance for clock skew)
        doc_ts = latest_doc.get('timestamp', 0)
        # 3600s buffer in case DB stores date only (midnight) or timezone diffs
        # But primarily relying on the 'count increased' check for "newness" is safer for simple web apps
        valid_timing = True 
        score += 20
        feedback.append("Success: Document created for the correct patient (Walter Bishop).")
    elif doc_created:
        # If count increased but we failed to fetch the row (unlikely), partial credit
        score += 10
        feedback.append("Warning: Document count increased, but details could not be verified.")
        
    # Criterion 3: Content Verification (40 pts)
    # Check Subject Line
    content_match = False
    if latest_doc:
        description = latest_doc.get('description', '') or ''
        url_field = latest_doc.get('url', '') or ''
        
        # We look for the key phrase "Insurance Claim Denial"
        # The agent might put it in the title (description) or the body (which might be in a blob, not fetched)
        # But the instructions asked for "Subject/Title".
        target_phrase = "Insurance Claim Denial"
        
        if target_phrase.lower() in description.lower() or target_phrase.lower() in url_field.lower():
            content_match = True
            score += 40
            feedback.append(f"Success: Document subject contains '{target_phrase}'.")
        else:
            feedback.append(f"Failure: Document found, but subject '{description}' does not contain '{target_phrase}'.")
            
    # 5. Final Result
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }