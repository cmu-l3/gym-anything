#!/usr/bin/env python3
"""
Verifier for enable_remote_mysql task.

Scoring Criteria:
1. Server Listening on All Interfaces (40 pts): MariaDB bind-address changed to 0.0.0.0.
2. User Access Granted (30 pts): User 'acmecorp' can connect from remote.
3. Service Running (20 pts): Service is active after changes.
4. Security Precision (10 pts): Access restricted to specific IP (192.168.100.55), not global wildcard (%).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_remote_mysql(traj, env_info, task_info):
    """
    Verify that MariaDB is configured for remote access for specific user/IP.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    
    # Criterion 1: Server Listening (40 pts)
    listening_all = result.get("listening_on_all", False)
    bind_addr = result.get("bind_address_detected", "unknown")
    
    if listening_all:
        score += 40
        feedback_parts.append(f"MariaDB listening on {bind_addr} (Correct)")
    else:
        feedback_parts.append(f"MariaDB listening on {bind_addr} (Expected 0.0.0.0 or ::)")

    # Criterion 2: User Access Granted (30 pts)
    access_granted = result.get("user_access_granted", False)
    
    if access_granted:
        score += 30
        feedback_parts.append("Remote user access granted")
    else:
        feedback_parts.append("User 'acmecorp' does not have remote access")

    # Criterion 3: Service Running (20 pts)
    # Crucial because changing config often breaks restart if typo exists
    service_running = result.get("service_running", False)
    if service_running:
        score += 20
        feedback_parts.append("MariaDB service is running")
    else:
        feedback_parts.append("MariaDB service is NOT running (check config syntax)")

    # Criterion 4: Security Precision (10 pts)
    specific_ip = result.get("specific_ip_used", False)
    wildcard = result.get("wildcard_used", False)
    
    if specific_ip:
        score += 10
        feedback_parts.append("Security: Access restricted to specific IP")
    elif wildcard:
        feedback_parts.append("Security: Access granted via Wildcard (%) - specific IP preferred")
        # No points for precision if wildcard used, but they got the access points
    
    # VLM Verification (Bonus/Confirmation)
    # Check if they used the UI
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_scr = get_final_screenshot(traj)
        
        vlm_prompt = (
            "The user is configuring MariaDB/MySQL for remote access. "
            "Look for: 1) Webmin/Virtualmin 'MySQL Server Configuration' page. "
            "2) 'Database Permissions' or 'Remote Hosts' page. "
            "3) Entry of IP '192.168.100.55'. "
            "Did the user perform these configuration steps?"
        )
        
        vlm_res = query_vlm(images=frames + [final_scr], prompt=vlm_prompt)
        if vlm_res.get("success") and "yes" in vlm_res.get("answer", "").lower():
            # Small bonus or just log it? Sticking to strict scoring for now.
            pass
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    # Pass Condition
    # Must be listening on all interfaces AND have access granted AND service running
    passed = (listening_all and access_granted and service_running and score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }