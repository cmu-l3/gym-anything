#!/usr/bin/env python3
"""
Verifier for export_risk_register task.

Verifies that:
1. A file was exported to the Downloads folder.
2. The file was created during the task window (anti-gaming).
3. The file contains expected keywords from the risk register (e.g., "Phishing").
4. Uses VLM to verify the UI interaction if file checks are ambiguous.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_risk_register(traj, env_info, task_info):
    # 1. Setup access to env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Extract metrics
    file_found = result.get('file_found', False)
    is_fresh = result.get('is_fresh', False)
    content_match = result.get('content_match', False)
    found_keywords = result.get('found_keywords', "")
    
    score = 0
    feedback = []

    # 4. Scoring Logic
    
    # Criterion 1: File Existence (40 pts)
    if file_found:
        score += 40
        feedback.append("Export file found in Downloads.")
    else:
        feedback.append("No export file found in /home/ga/Downloads.")

    # Criterion 2: Freshness (20 pts)
    # Only award if file found
    if file_found and is_fresh:
        score += 20
        feedback.append("File was created during the task.")
    elif file_found and not is_fresh:
        feedback.append("File timestamp indicates it is old (pre-task).")

    # Criterion 3: Content Verification (40 pts)
    if content_match:
        score += 40
        feedback.append(f"File contains correct risk data (found: {found_keywords}).")
    elif file_found:
        feedback.append("File found but expected keywords ('Phishing', 'Ransomware') were missing.")

    # 5. VLM Trajectory Verification (Fallback/Bonus Context)
    # If the file check passed perfectly, we might skip this or use it to confirm "clean" work.
    # If file check failed, this can help debug or give partial credit if UI failed but user tried.
    
    # We will use VLM to verify the "Export" workflow was attempted
    frames = sample_trajectory_frames(traj, n=5)
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze these screenshots of a user interacting with Eramba GRC software. "
        "Did the user navigate to the 'Risk Management' or 'Risks' section? "
        "Did they open an 'Export' menu or click an 'Export' button (often CSV or Excel icon)? "
        "Did a 'Save File' dialog appear? "
        "Answer 'Yes' or 'No' and explain."
    )
    
    # Only run VLM if we aren't at 100% yet, or to robustify the pass
    if score < 100:
        try:
            vlm_response = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
            if vlm_response and "yes" in str(vlm_response).lower():
                # If they tried but maybe file save failed technically, give small partial credit?
                # For now, we stick to strict file verification for passing, but append feedback.
                feedback.append("VLM analysis suggests proper navigation and export attempt.")
            else:
                feedback.append("VLM analysis did not clearly show the export workflow.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }