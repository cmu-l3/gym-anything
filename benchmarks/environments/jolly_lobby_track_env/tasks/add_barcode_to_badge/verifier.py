#!/usr/bin/env python3
"""
Verifier for add_barcode_to_badge task.

Verification Strategy:
1. VLM (Primary): Analyze trajectory to confirm the Badge Designer was opened and a barcode element was added to the canvas.
2. File System (Secondary): Check if a configuration/template file was saved/modified during the task window.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_barcode_to_badge(traj, env_info, task_info):
    """
    Verify that the agent added a barcode to the badge template.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    feedback_parts = []
    
    # 2. File System Verification (30 points)
    # Did the agent save a change to the system?
    template_found = result.get('template_file_found', False)
    keywords_found = result.get('keywords_found', "")
    
    if template_found:
        score += 15
        feedback_parts.append("Badge template file modified.")
        
        # Did the file contain barcode hints?
        if "barcode" in keywords_found:
            score += 15
            feedback_parts.append("Barcode configuration detected in file.")
        else:
            feedback_parts.append("File modified but no explicit barcode data found (binary file?).")
    else:
        feedback_parts.append("No saved template file detected.")

    # 3. VLM Verification (70 points)
    # Use trajectory to verify the workflow
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_images = frames + [final_frame] if final_frame else frames

    prompt = """
    You are verifying a software task in "Jolly Lobby Track".
    The user was asked to: "Add a barcode to the visitor badge template linked to Visitor ID".

    Review the screenshots of the agent's workflow. Answer the following questions:
    1. Did the agent open a "Badge Designer" or "Card Designer" window? (Look for a canvas with badge elements).
    2. Is a Barcode element visible on the badge design canvas? (Look for vertical lines or a QR code pattern).
    3. Is the barcode linked to a data field (e.g. "Visitor ID", "[ID]", "CardNo") or property? (Look at property panels or text overlay on the barcode).
    4. Did the agent perform a Save action?

    Return a JSON object with boolean keys:
    {
        "designer_opened": true/false,
        "barcode_visible": true/false,
        "data_linked": true/false,
        "save_action": true/false,
        "reasoning": "your reasoning here"
    }
    """

    vlm_result = query_vlm(images=all_images, prompt=prompt)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("designer_opened", False):
            score += 20
            feedback_parts.append("VLM: Badge Designer opened.")
        
        if parsed.get("barcode_visible", False):
            score += 30
            feedback_parts.append("VLM: Barcode element visible on badge.")
        else:
            feedback_parts.append("VLM: No barcode element seen on canvas.")
            
        if parsed.get("data_linked", False):
            score += 10
            feedback_parts.append("VLM: Data binding observed.")
            
        if parsed.get("save_action", False):
            score += 10
            feedback_parts.append("VLM: Save action observed.")
    else:
        feedback_parts.append("VLM verification failed to run.")

    # 4. Final Scoring
    # Pass if score >= 65 AND (Barcode Visible OR File modified with barcode data)
    pass_threshold = 65
    barcode_evidence = parsed.get("barcode_visible", False) or ("barcode" in keywords_found)
    
    passed = (score >= pass_threshold) and barcode_evidence

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }