#!/usr/bin/env python3
"""Verifier for configure_system_smtp_relay task."""

import json
import tempfile
import os


def verify_system_smtp(traj, env_info, task_info):
    """Verify that FreeScout system mail settings are configured correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_driver = metadata.get('expected_driver', 'smtp')
    expected_host = metadata.get('expected_host', '127.0.0.1')
    expected_port = metadata.get('expected_port', '1025')
    expected_from_email = metadata.get('expected_from_email', 'notifications@helpdesk.local')
    expected_from_name = metadata.get('expected_from_name', 'Internal Helpdesk')

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
    
    # 1. Mail Driver (20 pts)
    actual_driver = result.get('mail_driver', '').lower()
    if actual_driver == expected_driver.lower():
        score += 20
        feedback_parts.append("Mail Driver correct")
    else:
        feedback_parts.append(f"Mail Driver mismatch: expected '{expected_driver}', got '{actual_driver}'")

    # 2. Host (20 pts)
    actual_host = result.get('mail_host', '')
    if actual_host == expected_host:
        score += 20
        feedback_parts.append("Host correct")
    else:
        feedback_parts.append(f"Host mismatch: expected '{expected_host}', got '{actual_host}'")

    # 3. Port (20 pts)
    actual_port = str(result.get('mail_port', ''))
    if actual_port == expected_port:
        score += 20
        feedback_parts.append("Port correct")
    else:
        feedback_parts.append(f"Port mismatch: expected '{expected_port}', got '{actual_port}'")

    # 4. From Email & Name (20 pts)
    actual_email = result.get('mail_from_address', '')
    actual_name = result.get('mail_from_name', '')
    
    if actual_email == expected_from_email and actual_name == expected_from_name:
        score += 20
        feedback_parts.append("Sender identity correct")
    else:
        if actual_email != expected_from_email:
            feedback_parts.append(f"From Email mismatch: expected '{expected_from_email}', got '{actual_email}'")
        if actual_name != expected_from_name:
            feedback_parts.append(f"From Name mismatch: expected '{expected_from_name}', got '{actual_name}'")

    # 5. Encryption & Auth (20 pts)
    # Expected: Encryption None (empty/null) and Username empty
    actual_encryption = result.get('mail_encryption', '')
    actual_username = result.get('mail_username', '')
    
    enc_ok = not actual_encryption or actual_encryption.lower() == 'null' or actual_encryption.lower() == 'none'
    auth_ok = not actual_username
    
    if enc_ok and auth_ok:
        score += 20
        feedback_parts.append("Encryption/Auth settings correct")
    else:
        if not enc_ok:
            feedback_parts.append(f"Encryption should be empty/null, got '{actual_encryption}'")
        if not auth_ok:
            feedback_parts.append(f"Username should be empty, got '{actual_username}'")

    # Bonus/Validation check (not strictly scored but good for feedback)
    if result.get('smtp_connection_detected', False):
        feedback_parts.append("(Verified: Connection to relay detected)")

    # Strict pass: All settings must be correct for mail to work
    passed = score == 100

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }