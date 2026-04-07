#!/usr/bin/env python3
"""
Verifier for the firefox_tls_cert_export task.

Verification Strategy:
1. Check if a .pem file exists in the Downloads directory.
2. Verify the file was created during the task (timestamp check).
3. Validate the .pem file cryptographically using the subject line to ensure it matches 'wikipedia.org'.
4. Confirm browser history indicates navigation to wikipedia.org and the about:certificate page.
5. VLM verification on the trajectory frames to verify the UI interaction.
"""

import json
import os
import tempfile
import logging

# Ensure VLM utilities are available
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    logging.warning("gym_anything.vlm not available. VLM checks will be skipped.")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tls_cert_export(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    expected_domain = task_info.get('metadata', {}).get('expected_domain', 'wikipedia.org')
    
    # 1. Retrieve the exported JSON from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    pem_exists = result.get('pem_exists', False)
    pem_created = result.get('pem_created_during_task', False)
    cert_subject = result.get('cert_subject', '')
    wiki_visited = result.get('wiki_visited', False)
    cert_visited = result.get('cert_viewer_visited', False)

    # Criterion 1: File Existence (15 points)
    if pem_exists:
        score += 15
        feedback_parts.append("PEM file found in Downloads.")
    else:
        feedback_parts.append("PEM file NOT found.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Created during task (15 points - anti-gaming)
    if pem_created:
        score += 15
        feedback_parts.append("File was created during task.")
    else:
        feedback_parts.append("File existed before task started (possible cheating).")

    # Criterion 3: Cryptographic Validation (25 points)
    # The subject of the cert MUST contain the expected domain
    if expected_domain.lower() in cert_subject.lower():
        score += 25
        feedback_parts.append(f"Valid cert subject matches '{expected_domain}'.")
    else:
        feedback_parts.append(f"Cert subject invalid or mismatch. Found: {cert_subject}")

    # Criterion 4: Browser History Evidence (15 points)
    if wiki_visited and cert_visited:
        score += 15
        feedback_parts.append("Browser history confirms workflow.")
    elif wiki_visited:
        score += 5
        feedback_parts.append("Wikipedia visited, but certificate page not in history.")
    else:
        feedback_parts.append("Browser history does not show Wikipedia visit.")

    # Criterion 5: VLM Trajectory Verification (30 points)
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        all_frames = frames + [final_frame] if final_frame else frames
        
        prompt = (
            "You are grading a web browser automation task. Look at these screenshots representing a timeline of actions. "
            f"Did the user successfully navigate to {expected_domain}, open the browser's Security/Certificate tools, "
            "and view/download the TLS certificate? "
            "Return JSON: {\"shows_workflow\": true/false, \"reason\": \"string\"}"
        )
        
        vlm_resp = query_vlm(images=all_frames, prompt=prompt)
        parsed = vlm_resp.get("parsed", {})
        shows_workflow = parsed.get("shows_workflow", False)
        
        if shows_workflow:
            score += 30
            feedback_parts.append("VLM visual verification passed.")
        else:
            feedback_parts.append(f"VLM verification failed: {parsed.get('reason', 'No visual evidence')}")
            
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # Give partial credit if VLM fails but programmatic checks are perfect
        if score == 70:
            score += 20
            feedback_parts.append("VLM skipped; programmatic checks passed.")

    # Determine passing state
    # Must have downloaded the file, file must be new, and it must belong to Wikipedia
    key_criteria_met = pem_exists and pem_created and (expected_domain.lower() in cert_subject.lower())
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }