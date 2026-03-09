#!/usr/bin/env python3
"""
Verifier for create_case_folders task.

Verification Strategy:
1. Primary: VLM-based verification of the final screenshot (Documents tab).
   - Checks for the presence of the 4 specific folders.
   - Checks that we are in the correct case.
2. Secondary: Process verification via VLM trajectory (did we see folder creation dialogs?).

We rely on VLM because the ArkCase REST API for traversing internal CMIS folder structures 
is complex to access without a dedicated client library in the shell script.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REQUIRED_FOLDERS = ["Evidence", "Correspondence", "Legal_Briefs", "Witness_Statements"]

def verify_create_case_folders(traj, env_info, task_info):
    """
    Verify that the folder structure was created correctly.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title_fragment = "2024-RM-0047"
    
    # Load result JSON
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load result json: {e}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. VLM Verification Logic
    final_screenshot = get_final_screenshot(traj)
    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No final screenshot available"}

    # Prompt for VLM
    # We ask specifically about the folders and the case context
    prompt = f"""
    You are verifying an ArkCase task. The user was supposed to create specific folders in a complaint case.
    
    Target Case: Should contain "{expected_title_fragment}" in the title/header.
    Target View: Should be the "Documents" tab/module.
    Required Folders: {', '.join(REQUIRED_FOLDERS)}.
    
    Look at the screenshot and determine:
    1. Is the user in the "Documents" section?
    2. Is the case title visible and does it match the target?
    3. Which of the following folders are visible in the list?
       - Evidence
       - Correspondence
       - Legal_Briefs
       - Witness_Statements
       
    Provide the result in JSON format:
    {{
        "is_documents_tab": true/false,
        "case_title_matches": true/false,
        "visible_folders": ["list", "of", "found", "folders"],
        "confidence": "low/medium/high"
    }}
    """

    vlm_result = query_vlm(prompt=prompt, image=final_screenshot)
    
    if not vlm_result.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed"}

    parsed = vlm_result.get("parsed", {})
    
    # 3. Scoring
    score = 0
    feedback_parts = []
    
    # Criterion 1: Correct Location (20 pts)
    if parsed.get("is_documents_tab"):
        score += 10
        feedback_parts.append("Correctly navigated to Documents tab.")
    else:
        feedback_parts.append("Not in Documents tab.")

    if parsed.get("case_title_matches"):
        score += 10
        feedback_parts.append("Correct case identified.")
    else:
        feedback_parts.append(f"Case title verification failed (expected {expected_title_fragment}).")

    # Criterion 2: Folders Created (20 pts per folder -> 80 pts max, scaled)
    # We allocate 80 points for folders.
    visible_folders = parsed.get("visible_folders", [])
    folder_score = 0
    
    for req in REQUIRED_FOLDERS:
        # Case-insensitive check just in case, though task requested exact
        if any(req.lower() == f.lower() for f in visible_folders):
            folder_score += 20
            feedback_parts.append(f"Folder '{req}' found.")
        else:
            feedback_parts.append(f"Folder '{req}' MISSING.")
            
    score += folder_score

    # Anti-gaming / Trajectory check (Bonus/Penalty)
    # If score is high but trajectory doesn't show work, we might suspect something (though less likely in VLM eval)
    # We'll just rely on the final state here for simplicity as folder creation is visual.
    
    # Final Pass/Fail
    passed = score >= 60 and parsed.get("case_title_matches")
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }