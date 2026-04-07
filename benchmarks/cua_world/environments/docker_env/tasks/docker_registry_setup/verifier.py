#!/usr/bin/env python3
"""
Verifier for docker_registry_setup task.

Verification Logic:
1. Container State (Running, Ports, Volume) - 20 pts
2. Security Configuration (TLS, Auth Files, Enforcement) - 30 pts
3. Content Verification (Repositories, Tags, Integrity) - 40 pts
4. Tooling (Catalog script) - 10 pts

Anti-Gaming:
- Checks if container uses correct image
- Verifies TLS responds on port 5443
- Verifies Auth rejects unauthenticated requests
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_registry_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/safe_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Container Infrastructure (20 pts)
    if result.get("is_running") and result.get("port_mapping_correct"):
        score += 15
        feedback_parts.append("Registry container running on port 5443")
    else:
        feedback_parts.append("Registry container NOT running correctly on 5443")

    if result.get("volume_mounted"):
        score += 5
        feedback_parts.append("Volume mounted")
    else:
        feedback_parts.append("Data volume missing")

    # 2. Security Config (30 pts)
    security_score = 0
    if result.get("certs_exist") and result.get("tls_working"):
        security_score += 10
        feedback_parts.append("TLS configured")
    else:
        feedback_parts.append("TLS missing/broken")

    if result.get("auth_exists") and result.get("auth_users_correct"):
        security_score += 10
        feedback_parts.append("Auth file correct")
    
    if result.get("auth_enforced") and result.get("catalog_accessible"):
        security_score += 10
        feedback_parts.append("Auth enforcement working")
    else:
        feedback_parts.append("Auth enforcement failed (or login failed)")
        
    score += security_score

    # 3. Content & Integrity (40 pts)
    if result.get("repo_count_correct"):
        score += 20
        feedback_parts.append("All 3 repositories pushed")
    else:
        feedback_parts.append("Missing repositories")

    if result.get("tags_correct"):
        score += 10
        feedback_parts.append("Tags follow convention")
    
    if result.get("image_integrity"):
        score += 10
        feedback_parts.append("Image pull verification passed")
    else:
        feedback_parts.append("Image verification failed (pull or tag mismatch)")

    # 4. Tooling (10 pts)
    if result.get("catalog_script_exists"):
        score += 10
        feedback_parts.append("Catalog script created")
    else:
        feedback_parts.append("Catalog script missing")

    # Final Evaluation
    passed = score >= 60 and result.get("tls_working") and result.get("repo_count_correct")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }