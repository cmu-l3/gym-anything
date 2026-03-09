#!/usr/bin/env python3
"""
Verifier for register_oauth_application task.

Checks:
1. Database Record: An OAuth2 application named "SkyLinks GCS" exists.
2. Configuration: It has 'confidential' client type and 'client-credentials' grant type.
3. Ownership: It belongs to 'admin'.
4. File Output: The agent saved a file with credentials.
5. Data Integrity: The Client ID in the file matches the Client ID in the database (Anti-gaming).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_oauth_application(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    
    db_record = result.get("db_record")
    file_exists = result.get("file_exists", False)
    file_content = result.get("file_content", "")

    # 1. Check DB Record Existence (30 pts)
    if db_record:
        score += 30
        feedback_parts.append("Database record created.")
    else:
        feedback_parts.append("No 'SkyLinks GCS' application found in database.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check Configuration (20 pts)
    config_score = 0
    # Client Type
    if db_record.get("client_type") == "confidential":
        config_score += 10
    else:
        feedback_parts.append(f"Wrong client type: {db_record.get('client_type')}")

    # Grant Type
    if db_record.get("authorization_grant_type") == "client-credentials":
        config_score += 10
    else:
        feedback_parts.append(f"Wrong grant type: {db_record.get('authorization_grant_type')}")
    
    # Owner
    if db_record.get("user") == "admin":
        # Bonus/Requirement implicit in task, not heavily weighted but good to check
        pass 
    else:
        feedback_parts.append(f"Warning: App owner is {db_record.get('user')}, expected admin.")

    score += config_score
    if config_score == 20:
        feedback_parts.append("Configuration correct.")

    # 3. Check File Existence (10 pts)
    if file_exists:
        score += 10
        feedback_parts.append("Credential file created.")
    else:
        feedback_parts.append("Credential file NOT created.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 4. Check Data Integrity (40 pts)
    # Parse file content
    import re
    
    # Look for Client ID
    # Regex allows for "Client ID:", "Client ID", "id:", etc. followed by the alphanumeric string
    client_id_match = re.search(r'Client\s*I[Dd][: ]+\s*([a-zA-Z0-9]+)', file_content)
    file_client_id = client_id_match.group(1) if client_id_match else None
    
    # Look for Client Secret
    client_secret_match = re.search(r'Client\s*Secret[: ]+\s*([a-zA-Z0-9\-_]+)', file_content)
    file_client_secret = client_secret_match.group(1) if client_secret_match else None

    # Verify ID match
    db_client_id = db_record.get("client_id")
    
    if file_client_id and db_client_id and file_client_id.strip() == db_client_id.strip():
        score += 30
        feedback_parts.append("Client ID in file matches database.")
    else:
        feedback_parts.append(f"Client ID mismatch or missing. File: {file_client_id}, DB: {db_client_id}")

    # Verify Secret presence
    if file_client_secret and len(file_client_secret) > 10:
        score += 10
        feedback_parts.append("Client Secret appears valid in file.")
    else:
        feedback_parts.append("Client Secret missing or too short in file.")

    # Final logic
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }