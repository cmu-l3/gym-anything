#!/usr/bin/env python3
"""
Verifier for decommission_encrypted_volume task.
Evaluates if the agent securely extracted data, verified integrity, destroyed the container, and reported action.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_decommission_encrypted_volume(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. File Export & Integrity (30 pts)
    integrity_count = result.get("files_integrity_match", 0)
    if integrity_count == 3:
        score += 30
        feedback_parts.append("All files exported with integrity")
    elif integrity_count > 0:
        pts = integrity_count * 10
        score += pts
        feedback_parts.append(f"{integrity_count}/3 files exported correctly")
    else:
        feedback_parts.append("No files exported correctly")

    # 2. Checksum Manifest (15 pts)
    if result.get("manifest_exists"):
        if result.get("manifest_correct"):
            score += 15
            feedback_parts.append("Checksum manifest correct")
        elif result.get("manifest_valid"):
            score += 10
            feedback_parts.append("Checksum manifest valid format but incorrect hashes")
        else:
            score += 5
            feedback_parts.append("Checksum manifest exists but invalid")
    else:
        feedback_parts.append("Checksum manifest missing")

    # 3. Volume Dismounted (10 pts)
    if result.get("volume_dismounted"):
        score += 10
        feedback_parts.append("Volume dismounted")
    else:
        feedback_parts.append("Volume still mounted")

    # 4. Container Destroyed (25 pts)
    # This is the most critical security step
    if result.get("container_destroyed"):
        score += 25
        feedback_parts.append("Container securely destroyed")
    else:
        status = result.get("container_status", "unknown")
        feedback_parts.append(f"Container NOT destroyed (status: {status})")

    # 5. Decommission Report (20 pts)
    if result.get("report_exists"):
        content_score = result.get("report_content_score", 0)
        # 5 points for existence + up to 15 for content (3 pts per item matched in export script)
        report_points = 5 + (content_score * 3)
        if report_points > 20: report_points = 20
        score += report_points
        feedback_parts.append(f"Report created (quality: {content_score}/5 items)")
    else:
        feedback_parts.append("Report missing")

    # Pass logic: Must have exported all files AND destroyed container
    passed = (score >= 70) and (integrity_count == 3) and result.get("container_destroyed")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }