#!/usr/bin/env python3
"""
Verifier for find_artifact_checksum task.

Verifies that:
1. The output file exists and was created during the task.
2. The content matches the authoritative SHA-256 checksum from Artifactory.
3. The agent actually navigated the UI to find it (via VLM).
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_find_artifact_checksum(traj, env_info, task_info):
    """
    Verify the artifact checksum task.
    """
    # 1. Setup and Copy Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract Data
    submitted_content = result_data.get("submitted_content", "").strip().lower()
    authoritative_sha256 = result_data.get("authoritative_sha256", "").strip().lower()
    file_exists = result_data.get("file_exists", False)
    file_fresh = result_data.get("file_created_during_task", False)

    score = 0
    feedback_parts = []

    # 3. Verify File Existence & Format (20 points)
    if file_exists and file_fresh:
        score += 10
        feedback_parts.append("Output file created.")
        
        # Check format (64 hex chars)
        if re.fullmatch(r'[0-9a-f]{64}', submitted_content):
            score += 10
            feedback_parts.append("Format is valid SHA-256 hex string.")
        else:
            feedback_parts.append("Format incorrect (expected 64 hex characters).")
    elif file_exists:
        feedback_parts.append("Output file exists but was not created during this task (stale).")
    else:
        feedback_parts.append("Output file not found.")

    # 4. Verify Content Accuracy (40 points)
    # The checksum must match exactly
    if authoritative_sha256 and submitted_content == authoritative_sha256:
        score += 40
        feedback_parts.append("Checksum value is correct.")
    else:
        feedback_parts.append(f"Checksum mismatch. Expected first 8 chars: {authoritative_sha256[:8]}...")

    # 5. VLM Verification of Trajectory (40 points)
    # We want to see evidence of UI navigation, not just a lucky guess or curl command
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    vlm_prompt = """
    You are verifying an agent operating JFrog Artifactory. 
    The goal is to find the SHA-256 checksum of 'commons-lang3-3.14.0.jar' in the artifact tree.

    Look at the sequence of screenshots. Answer the following checks:
    1. Did the agent navigate to the "Artifacts" page (showing the tree browser)?
    2. Did the agent expand the repository 'example-repo-local' and browse the folder structure?
    3. Did the agent click/select the specific file 'commons-lang3-3.14.0.jar'?
    4. Did the 'General' or 'Checksums' info panel appear showing file details?

    Return valid JSON:
    {
        "visited_artifacts_page": boolean,
        "browsed_tree": boolean,
        "selected_target_jar": boolean,
        "viewed_details_panel": boolean,
        "explanation": "string"
    }
    """

    try:
        vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_data = vlm_response.get("parsed", {})
        
        vlm_score = 0
        if vlm_data.get("visited_artifacts_page"): vlm_score += 10
        if vlm_data.get("browsed_tree"): vlm_score += 10
        if vlm_data.get("selected_target_jar"): vlm_score += 10
        if vlm_data.get("viewed_details_panel"): vlm_score += 10
        
        score += vlm_score
        feedback_parts.append(f"UI Navigation Score: {vlm_score}/40")
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if data is correct, assume they did it right, give partial VLM credit
        if score >= 50: 
            score += 20
            feedback_parts.append("VLM check unavailable, granting partial process credit.")

    # 6. Final Assessment
    # Pass threshold: 60 points (Needs correct checksum + some file/format points OR perfect process)
    passed = score >= 60 and (submitted_content == authoritative_sha256)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }