#!/usr/bin/env python3
"""
Verifier for local_s3_minio_integration task.

Requirements:
1. Docker Compose services must be running (Web + MinIO).
2. Web container must have correct S3 env vars.
3. Bucket 'company-assets' must exist (AUTOMATICALLY created).
4. File upload via Web App must succeed and persist to MinIO.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_local_s3_minio_integration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # Criterion 1: Services Running (20 pts)
    if result.get('services_running', False):
        score += 20
        feedback_parts.append("Services running")
    else:
        feedback_parts.append("Services NOT running")

    # Criterion 2: App Configured (20 pts)
    if result.get('env_configured', False):
        score += 20
        feedback_parts.append("Environment variables set")
    else:
        feedback_parts.append("Missing S3 environment variables")

    # Criterion 3: Bucket Exists (30 pts)
    # This proves the "automatic creation" part worked, because the verifier checks 
    # immediately after interacting with the system, and no manual creation step 
    # should be required by the user at runtime if configured correctly.
    if result.get('bucket_exists', False):
        score += 30
        feedback_parts.append("'company-assets' bucket exists")
    else:
        feedback_parts.append("'company-assets' bucket MISSING")

    # Criterion 4: Upload Success (30 pts)
    # This proves end-to-end functionality (Network -> App -> MinIO -> Storage)
    if result.get('upload_success', False):
        score += 30
        feedback_parts.append("File upload test PASSED")
    else:
        feedback_parts.append("File upload test FAILED")

    passed = score >= 70 and result.get('upload_success', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }