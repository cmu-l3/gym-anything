#!/usr/bin/env python3
"""
Verifier for delete_artifact task in JFrog Artifactory.
Verifies that the specific target artifact was deleted while others were preserved.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_artifact(traj, env_info, task_info):
    """
    Verify artifact deletion.
    
    Scoring:
    - Target artifact deleted (40 pts)
    - Target folder cleaned up (15 pts)
    - Other artifact preserved (25 pts)
    - VLM: Verified UI navigation/deletion action (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Target Deletion (40 pts)
    # 404 means Not Found (Deleted), which is Good
    lang3_status = result.get('final_lang3_status', 0)
    if lang3_status == 404:
        score += 40
        feedback_parts.append("Target artifact deleted successfully")
    elif lang3_status == 200:
        feedback_parts.append("Target artifact still exists")
    else:
        feedback_parts.append(f"Target artifact has unexpected status: {lang3_status}")

    # 2. Verify Folder Cleanup (15 pts)
    # If the user deleted the artifact properly via UI, Artifactory usually cleans empty folders
    # or the user deleted the folder itself.
    folder_status = result.get('final_folder_status', 0)
    if folder_status == 404:
        score += 15
        feedback_parts.append("Artifact folder cleaned up")
    else:
        feedback_parts.append("Artifact folder still exists (partial deletion)")

    # 3. Verify Preservation (25 pts)
    # 200 means Found (Preserved), which is Good
    io_status = result.get('final_io_status', 0)
    if io_status == 200:
        score += 25
        feedback_parts.append("Other artifact preserved intact")
    else:
        feedback_parts.append("CRITICAL: You deleted the wrong artifact! (commons-io missing)")
        # Heavy penalty implies strict requirement
        score = 0 

    # 4. Anti-Gaming Check
    initial_lang3 = result.get('initial_lang3_status', 0)
    if initial_lang3 != 200:
        feedback_parts.append("Warning: Initial setup failed (target wasn't present at start)")
        # Don't fail the agent for setup issues, but note it.

    # 5. VLM Verification (20 pts)
    # Use trajectory to ensure they used the UI (Delete dialog, tree navigation)
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_images = frames + ([final_frame] if final_frame else [])
    
    vlm_score = 0
    if all_images and query_vlm:
        prompt = """
        Review these screenshots of a user interacting with JFrog Artifactory.
        The user was tasked with deleting a specific artifact from the tree browser.
        
        Look for:
        1. Navigation in the "Artifacts" tree browser (folders expanded).
        2. A context menu (right-click) or "Actions" menu open.
        3. A "Delete" confirmation dialog box visible in any frame.
        
        Return JSON:
        {
            "tree_navigation_visible": true/false,
            "delete_dialog_seen": true/false
        }
        """
        try:
            vlm_res = query_vlm(prompt=prompt, images=all_images)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('tree_navigation_visible', False):
                vlm_score += 10
                feedback_parts.append("VLM: Tree navigation confirmed")
            
            if parsed.get('delete_dialog_seen', False):
                vlm_score += 10
                feedback_parts.append("VLM: Deletion dialog confirmed")
                
        except Exception as e:
            # Fallback if VLM fails - award partial points if technical success is high
            if score >= 65:
                vlm_score = 10
                feedback_parts.append("VLM verification skipped (error), awarded partial credit")
    
    score += vlm_score

    # Pass Threshold: Need at least 75 (Must delete target + preserve other + some cleanup/VLM)
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }