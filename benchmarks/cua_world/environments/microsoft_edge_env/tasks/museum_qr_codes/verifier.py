#!/usr/bin/env python3
"""
Verifier for museum_qr_codes task.
Checks if QR codes exist, decode to correct URLs, and manifest is accurate.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_museum_qr_codes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define targets and expected URL fragments
    targets = {
        "eniac": "wikipedia.org/wiki/ENIAC",
        "hopper": "wikipedia.org/wiki/Grace_Hopper",
        "transistor": "wikipedia.org/wiki/Transistor"
    }

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
    
    files_data = result.get("files", {})
    manifest_data = result.get("manifest", {})

    # 1. Check Files Existence and Timing (10 pts)
    all_files_exist = True
    all_fresh = True
    for key in targets:
        f_info = files_data.get(key, {})
        if not f_info.get("exists", False):
            all_files_exist = False
            feedback.append(f"Missing file: {f_info.get('filename', 'unknown')}")
        if not f_info.get("created_during_task", False):
            all_fresh = False
    
    if all_files_exist:
        score += 5
        if all_fresh:
            score += 5
            feedback.append("All QR image files created during task.")
        else:
            feedback.append("Files exist but timestamps are stale.")
    else:
        feedback.append("Some QR image files are missing.")

    # 2. Check Valid Images (15 pts)
    all_valid_images = True
    for key in targets:
        f_info = files_data.get(key, {})
        if not f_info.get("valid_image", False):
            all_valid_images = False
            if f_info.get("exists"):
                feedback.append(f"File {f_info.get('filename')} is not a valid image/QR.")
    
    if all_files_exist and all_valid_images:
        score += 15
        feedback.append("All files are valid images.")

    # 3. Check QR Content (20 pts per file = 60 pts)
    for key, expected_fragment in targets.items():
        f_info = files_data.get(key, {})
        decoded = f_info.get("decoded_url", "").lower()
        
        if expected_fragment.lower() in decoded:
            score += 20
            feedback.append(f"QR Code for {key.upper()} is correct.")
        else:
            if f_info.get("exists"):
                feedback.append(f"QR Code for {key.upper()} points to wrong URL: {decoded}")
            else:
                feedback.append(f"QR Code for {key.upper()} missing.")

    # 4. Check Manifest (15 pts)
    if manifest_data.get("exists", False):
        content = manifest_data.get("content", "").lower()
        manifest_score = 0
        # Check if it mentions filenames and urls
        if "eniac_qr.png" in content and "wikipedia.org/wiki/eniac" in content:
            manifest_score += 5
        if "hopper_qr.png" in content and "wikipedia.org/wiki/grace_hopper" in content:
            manifest_score += 5
        if "transistor_qr.png" in content and "wikipedia.org/wiki/transistor" in content:
            manifest_score += 5
        
        score += manifest_score
        if manifest_score == 15:
            feedback.append("Manifest file contains all correct mappings.")
        elif manifest_score > 0:
            feedback.append("Manifest file partial match.")
        else:
            feedback.append("Manifest file exists but content incorrect.")
    else:
        feedback.append("Manifest file missing.")

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }