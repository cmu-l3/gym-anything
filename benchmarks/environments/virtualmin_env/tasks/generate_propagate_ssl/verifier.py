#!/usr/bin/env python3
"""
Verifier for generate_propagate_ssl task.
Checks if the self-signed certificate was generated with correct details
and applied to system services.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_propagate_ssl(traj, env_info, task_info):
    """
    Verify the SSL generation and propagation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Domain Certificate Details (30 pts)
    domain_cert_exists = result.get('domain_cert_exists', False)
    domain_subject = result.get('domain_cert_subject', '')
    created_during_task = result.get('file_created_during_task', False)

    if not domain_cert_exists:
        return {"passed": False, "score": 0, "feedback": "No domain certificate found."}

    # Anti-gaming check
    if not created_during_task:
        feedback_parts.append("WARNING: Certificate file was not modified during the task.")
    else:
        score += 5 # Points for actually generating a file
        feedback_parts.append("Certificate generated during task.")

    # Check Subject details
    # Subject format looks like: C=US, ST=California, L=San Francisco, O=Acme Corp, OU=IT Dept, CN=acmecorp.test
    subject_score = 0
    if "O=Acme Corp" in domain_subject or "O = Acme Corp" in domain_subject:
        subject_score += 10
        feedback_parts.append("Organization correct.")
    else:
        feedback_parts.append(f"Organization incorrect (Found: {domain_subject})")

    if "San Francisco" in domain_subject:
        subject_score += 5
        feedback_parts.append("City correct.")
    
    if "IT Dept" in domain_subject:
        subject_score += 5
        feedback_parts.append("Department correct.")
        
    if "CN=acmecorp.test" in domain_subject or "CN = acmecorp.test" in domain_subject:
        subject_score += 5
        feedback_parts.append("Common Name correct.")

    score += subject_score

    # 2. Verify Propagation (Modulus Matching)
    domain_modulus = result.get('domain_cert_modulus', 'DOMAIN_MISSING')
    webmin_modulus = result.get('webmin_cert_modulus', 'WEBMIN_MISSING')
    postfix_modulus = result.get('postfix_cert_modulus', 'POSTFIX_MISSING')
    dovecot_modulus = result.get('dovecot_cert_modulus', 'DOVECOT_MISSING')

    if domain_modulus == 'DOMAIN_MISSING':
         return {"passed": False, "score": score, "feedback": "Invalid domain cert modulus."}

    # Check Webmin (25 pts)
    if webmin_modulus == domain_modulus:
        score += 25
        feedback_parts.append("Webmin updated successfully.")
    else:
        feedback_parts.append("Webmin NOT updated.")

    # Check Postfix (20 pts)
    if postfix_modulus == domain_modulus:
        score += 20
        feedback_parts.append("Postfix updated successfully.")
    else:
        feedback_parts.append("Postfix NOT updated.")

    # Check Dovecot (25 pts)
    if dovecot_modulus == domain_modulus:
        score += 25
        feedback_parts.append("Dovecot updated successfully.")
    else:
        feedback_parts.append("Dovecot NOT updated.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }