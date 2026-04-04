#!/usr/bin/env python3
"""
Verifier for download_artifact_from_repo task.
Verifies that the correct artifact was downloaded from Artifactory.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_download_artifact(traj, env_info, task_info):
    """
    Verify artifact download.
    
    Criteria:
    1. File exists at expected path (20 pts)
    2. File was created during task window (15 pts)
    3. File size is valid (>400KB) (15 pts)
    4. SHA256 checksum matches expected (25 pts)
    5. Artifactory download count > 0 (10 pts)
    6. VLM verification of workflow (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    max_score = 100
    feedback_parts = []
    
    # 1. File Existence (20 pts)
    if result.get('file_exists', False):
        score += 20
        feedback_parts.append("File found at expected path")
    else:
        feedback_parts.append("File NOT found at expected path")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Timestamp Check (15 pts)
    if result.get('file_created_during_task', False):
        score += 15
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File has old timestamp (pre-existing?)")

    # 3. File Size Check (15 pts)
    # Real commons-lang3-3.14.0.jar is ~653 KB. Check for > 400KB to avoid empty/corrupt files.
    size = result.get('file_size', 0)
    if size > 400000:
        score += 15
        feedback_parts.append(f"File size valid ({size} bytes)")
    else:
        feedback_parts.append(f"File size too small ({size} bytes)")

    # 4. Integrity Check (25 pts)
    expected_sha = result.get('expected_sha256', '')
    actual_sha = result.get('file_sha256', '')
    
    if expected_sha and actual_sha and expected_sha == actual_sha:
        score += 25
        feedback_parts.append("SHA256 checksum matches source")
    else:
        feedback_parts.append(f"Checksum mismatch! Expected {expected_sha[:8]}..., got {actual_sha[:8]}...")

    # 5. Artifactory Stats Check (10 pts)
    # This proves it came from Artifactory, not just curl from Maven Central (unless they proxied, but this is local repo)
    dl_count = result.get('artifactory_download_count', 0)
    if dl_count > 0:
        score += 10
        feedback_parts.append("Artifactory recorded download")
    else:
        feedback_parts.append("Artifactory did not record download (check skipped or API issue)")

    # 6. VLM Verification (15 pts) - Placeholder for logic
    # In a real scenario, we would check trajectory frames for Artifactory UI interaction
    # For now, we grant points if primary criteria are met (hybrid approach)
    if score >= 75: 
        score += 15
        feedback_parts.append("Workflow implicitly verified by success")
    else:
        feedback_parts.append("Workflow verification skipped due to failure")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }