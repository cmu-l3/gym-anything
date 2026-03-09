#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_settings(traj, env_info, task_info):
    """
    Verifies that the hospital name and email were updated in the configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Grand Oak Community Hospital")
    expected_email = metadata.get('expected_email', "admin@grandoak.org")

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Analyze results
    config_docs = result.get('config_documents', [])
    
    if not config_docs:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No configuration documents found in database."
        }

    # Find the best matching doc
    best_doc = None
    name_match = False
    email_match = False
    
    for doc in config_docs:
        # Check Name
        doc_name = doc.get('hospitalName', '')
        if doc_name and expected_name.lower() in doc_name.lower():
            name_match = True
            
        # Check Email
        doc_email = doc.get('hospitalEmail', '')
        if doc_email and expected_email.lower() in doc_email.lower():
            email_match = True
            
        if name_match or email_match:
            best_doc = doc
            # If both match, we can stop searching
            if name_match and email_match:
                break
    
    # Calculate score
    score = 0
    feedback = []

    if name_match:
        score += 50
        feedback.append(f"Hospital name successfully updated to '{expected_name}'.")
    else:
        # Check what was found for debugging feedback
        found_names = [d.get('hospitalName') for d in config_docs]
        feedback.append(f"Hospital name not updated correctly. Found: {found_names}")

    if email_match:
        score += 50
        feedback.append(f"Hospital email successfully updated to '{expected_email}'.")
    else:
        found_emails = [d.get('hospitalEmail') for d in config_docs]
        feedback.append(f"Hospital email not updated correctly. Found: {found_emails}")

    # Pass threshold
    passed = (score >= 100)
    
    # Anti-gaming check: Ensure we found *something*
    if not best_doc:
        feedback.insert(0, "Configuration document did not contain target fields.")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }