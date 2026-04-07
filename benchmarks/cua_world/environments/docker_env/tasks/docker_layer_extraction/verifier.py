#!/usr/bin/env python3
"""
Verifier for docker_layer_extraction task.

Scoring Criteria:
1. File Recovery (30 pts): File exists on Desktop.
2. Content Verification (50 pts): File contains key proprietary strings.
3. Integrity Check (20 pts): File hash matches exact ground truth.

Anti-gaming:
- File must be created after task start.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_layer_extraction(traj, env_info, task_info):
    """
    Verifies that the agent recovered the deleted risk_model.py file.
    """
    # 1. Setup: Retrieve result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract metrics
    file_exists = result.get("file_exists", False)
    file_created_during_task = result.get("file_created_during_task", False)
    file_hash = result.get("file_hash", "")
    ground_truth_hash = result.get("ground_truth_hash", "expected_hash")
    strings_found = result.get("strings_found_count", 0)
    
    score = 0
    feedback_parts = []

    # 3. Evaluate
    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Recovery failed: 'risk_model.py' not found on Desktop."
        }

    # Criterion 1: Existence & Timestamp (30 pts)
    if file_exists and file_created_during_task:
        score += 30
        feedback_parts.append("File recovered successfully.")
    elif file_exists:
        # If it existed before task start, that's suspicious (or a restart), give partial credit if content is right
        score += 10
        feedback_parts.append("File exists but has old timestamp (pre-seeded?).")

    # Criterion 2: Content Verification (50 pts)
    # 3 strings total, approx 16.6 pts each
    content_points = 0
    if strings_found == 3:
        content_points = 50
        feedback_parts.append("All content checks passed.")
    elif strings_found == 2:
        content_points = 30
        feedback_parts.append("Partial content match (2/3 signatures found).")
    elif strings_found == 1:
        content_points = 15
        feedback_parts.append("Weak content match (1/3 signatures found).")
    else:
        feedback_parts.append("File content does not match expected Python code.")
    
    score += content_points

    # Criterion 3: Exact Hash Match (20 pts)
    # This proves they got the file from the layer, not just copy-pasted text from a guess
    if file_hash == ground_truth_hash and ground_truth_hash != "":
        score += 20
        feedback_parts.append("Perfect integrity: Checksum matches original source.")
    elif content_points > 0:
        feedback_parts.append("Checksum mismatch (content modified or partial recovery).")

    # 4. Final Verdict
    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 80)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }