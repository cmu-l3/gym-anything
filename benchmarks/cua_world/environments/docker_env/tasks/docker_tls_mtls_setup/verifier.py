#!/usr/bin/env python3
"""
Verifier for docker_tls_mtls_setup task.

Scoring System (100 points total):
- Cert Creation & Validity (35 pts):
  - CA exists and valid: 10
  - Server Cert signed by CA: 10
  - Client Cert signed by CA: 10
  - Server Cert has SAN: 5
- Infrastructure (20 pts):
  - Network exists: 5
  - Container running: 10
  - Files created during task: 5
- Functionality (mTLS) (30 pts):
  - Rejects connection without cert: 15
  - Accepts connection with cert: 15
- Documentation (15 pts):
  - Verification output file valid: 5
  - Documentation exists: 5
  - Documentation content check: 5

Pass Threshold: 65 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_tls_mtls_setup(traj, env_info, task_info):
    """Verify the mutual TLS setup between containers."""
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Cert Validity (35 pts)
    if result.get("has_ca_pair") and result.get("ca_valid"):
        score += 10
        feedback.append("CA certificate valid.")
    else:
        feedback.append("CA certificate missing or invalid.")

    if result.get("has_server_pair") and result.get("server_signed_by_ca"):
        score += 10
        feedback.append("Server certificate signed by CA.")
    else:
        feedback.append("Server certificate missing or not signed by CA.")

    if result.get("has_client_pair") and result.get("client_signed_by_ca"):
        score += 10
        feedback.append("Client certificate signed by CA.")
    else:
        feedback.append("Client certificate missing or not signed by CA.")

    if result.get("server_has_san"):
        score += 5
        feedback.append("Server certificate has correct SAN.")
    else:
        feedback.append("Server certificate missing SAN.")

    # 2. Infrastructure (20 pts)
    if result.get("network_exists"):
        score += 5
        feedback.append("Docker network created.")
    
    if result.get("container_running"):
        score += 10
        feedback.append("Nginx container running.")
    else:
        feedback.append("Nginx container NOT running.")

    if result.get("files_created_during_task"):
        score += 5
    else:
        feedback.append("Warning: Files appear to be pre-existing (anti-gaming check).")

    # 3. Functionality (30 pts)
    if result.get("mtls_rejects_no_cert"):
        score += 15
        feedback.append("mTLS enforced (rejected no-cert request).")
    else:
        feedback.append("Failed to enforce mTLS (did not reject no-cert request).")

    if result.get("mtls_accepts_cert"):
        score += 15
        feedback.append("mTLS working (accepted valid cert request).")
    else:
        feedback.append("mTLS failed (did not accept valid cert request).")

    # 4. Documentation (15 pts)
    if result.get("verif_file_exists") and result.get("verif_content_valid"):
        score += 5
        feedback.append("Verification output file verified.")
    
    if result.get("doc_file_exists"):
        score += 5
        if result.get("doc_content_valid"):
            score += 5
            feedback.append("Documentation looks complete.")
        else:
            feedback.append("Documentation exists but content seems sparse.")
    else:
        feedback.append("Documentation file missing.")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }