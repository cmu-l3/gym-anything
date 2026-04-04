#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_ssl_csr(traj, env_info, task_info):
    """
    Verify that the agent generated a valid CSR with the correct organization details.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    expected_subject = metadata.get('expected_subject', {})
    expected_key_size = metadata.get('expected_key_size', 2048)

    # Copy result file from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Initialize scoring
    score = 0
    feedback = []
    passed = False

    # 1. File Existence and Validity (30 points)
    if not result_data.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "CSR file was not created."}
    
    score += 10
    feedback.append("File created.")

    if result_data.get('valid_csr'):
        score += 20
        feedback.append("File is a valid CSR.")
    else:
        feedback.append("File is NOT a valid CSR format.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 2. Anti-Gaming (10 points)
    if result_data.get('file_created_during_task'):
        score += 10
        feedback.append("File created during task window.")
    else:
        feedback.append("Warning: File timestamp indicates it might be stale.")

    # 3. Subject Detail Verification (50 points)
    # Parse the raw subject string from OpenSSL
    # Example format: subject=C=US,ST=Washington,L=Seattle,O=Acme Corporation,OU=Web Operations,CN=acmecorp.test
    subject_raw = result_data.get('subject_raw', '')
    
    # Simple parser for OpenSSL subject output
    # Note: OpenSSL output format can vary slightly (spaces, separators), so we normalize
    subject_parts = {}
    
    # Remove 'subject=' prefix if present
    clean_subject = subject_raw.replace('subject=', '')
    
    # Split by comma (standard separator for one-line output) or slash (older openssl)
    # RFC2253 usually uses comma
    parts = clean_subject.split(',')
    
    for part in parts:
        part = part.strip()
        if '=' in part:
            key, val = part.split('=', 1)
            subject_parts[key.strip()] = val.strip()

    # Check fields
    fields_to_check = {
        'C': 'Country',
        'ST': 'State',
        'L': 'City',
        'O': 'Organization',
        'OU': 'Org Unit',
        'CN': 'Common Name'
    }

    # Email is sometimes in subject, sometimes separate, depends on config.
    # We'll check it if present in expected_subject
    if 'emailAddress' in expected_subject:
        fields_to_check['emailAddress'] = 'Email'

    field_scores = 50 / len(fields_to_check)
    
    for key, name in fields_to_check.items():
        expected_val = expected_subject.get(key)
        actual_val = subject_parts.get(key)
        
        if actual_val == expected_val:
            score += field_scores
        else:
            feedback.append(f"Incorrect {name}: expected '{expected_val}', got '{actual_val}'.")

    # 4. Key Size (10 points)
    actual_key = str(result_data.get('key_size', ''))
    if str(expected_key_size) in actual_key:
        score += 10
    else:
        feedback.append(f"Incorrect key size: expected {expected_key_size}, got {actual_key}.")

    # Round score
    score = int(round(score))
    
    # Pass threshold
    if score >= 80:
        passed = True
        feedback.append("Task completed successfully.")
    else:
        feedback.append("Task failed to meet all requirements.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }