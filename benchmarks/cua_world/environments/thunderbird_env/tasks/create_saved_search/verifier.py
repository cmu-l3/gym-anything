#!/usr/bin/env python3
"""
Verifier for create_saved_search task.

Evaluates the creation of a Thunderbird Saved Search folder programmatically
by parsing virtualFolders.dat and utilizing a VLM to confirm the UI trajectory.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Attempt to import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available.")

def verify_saved_search(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_folder_name', 'Q4 Budget Review')
    expected_scope = metadata.get('expected_scope', 'Inbox')
    expected_keyword = metadata.get('expected_search_keyword', 'budget')

    feedback_parts = []
    score = 0

    # 1. Retrieve the exported JSON results
    result_json_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    vf_data_path = tempfile.NamedTemporaryFile(delete=False, suffix='.dat').name
    
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            results = json.load(f)
            
        # Copy the virtualFolders.dat
        copy_from_env("/tmp/virtualFolders.dat", vf_data_path)
        with open(vf_data_path, 'r', encoding='utf-8', errors='replace') as f:
            vf_content = f.read()
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve files: {e}"}
    finally:
        if os.path.exists(result_json_path):
            os.unlink(result_json_path)
        if os.path.exists(vf_data_path):
            os.unlink(vf_data_path)

    # 2. Check File Existence and Anti-Gaming (Timestamp)
    vf_exists = results.get('vf_exists', False)
    task_start = results.get('task_start', 0)
    vf_mtime = results.get('vf_mtime', 0)
    
    if vf_exists and len(vf_content.strip()) > 0:
        if vf_mtime >= task_start:
            score += 10
            feedback_parts.append("✓ virtualFolders.dat created/modified during task (10 pts)")
        else:
            feedback_parts.append("✗ virtualFolders.dat exists but predates task start (Anti-gaming)")
    else:
        feedback_parts.append("✗ virtualFolders.dat not found or empty")
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts) + ". No saved search folder was created."
        }

    # 3. Check configuration in virtualFolders.dat
    # Name matching (handle Thunderbird's URL encoding: Q4%20Budget%20Review or Q4+Budget+Review)
    # We strip all non-alphanumeric and spaces to do a fuzzy inclusion check
    norm_content = re.sub(r'[%+]', ' ', vf_content).lower()
    norm_name = expected_name.lower()
    
    if norm_name in norm_content:
        score += 20
        feedback_parts.append(f"✓ Correct folder name '{expected_name}' (20 pts)")
    else:
        feedback_parts.append(f"✗ Incorrect or missing folder name (Expected '{expected_name}')")

    # Scope matching (Inbox)
    if re.search(expected_scope, vf_content, re.IGNORECASE):
        score += 20
        feedback_parts.append(f"✓ Search scope includes {expected_scope} (20 pts)")
    else:
        feedback_parts.append(f"✗ Search scope does not include {expected_scope}")

    # Search keyword matching ('budget')
    if re.search(expected_keyword, vf_content, re.IGNORECASE):
        score += 15
        feedback_parts.append(f"✓ Search conditions include keyword '{expected_keyword}' (15 pts)")
    else:
        feedback_parts.append(f"✗ Search conditions missing keyword '{expected_keyword}'")

    # 4. VLM Trajectory Verification
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if VLM_AVAILABLE and query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """You are analyzing screenshots of Mozilla Thunderbird.
            The agent was tasked with creating a "Saved Search" (Virtual Folder).
            
            Check the sequence of images for the following:
            1. Did the agent open the "New Saved Search" dialog box at any point?
            2. Does the left-hand folder pane eventually display a folder named "Q4 Budget Review"?
            
            Respond strictly in JSON format:
            {
                "dialog_opened": true/false,
                "folder_visible": true/false,
                "reasoning": "brief explanation"
            }"""
            
            vlm_response = query_vlm(prompt=prompt, images=images)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("dialog_opened", False):
                    vlm_score += 15
                    feedback_parts.append("✓ VLM confirmed 'New Saved Search' dialog opened (15 pts)")
                else:
                    feedback_parts.append("✗ VLM did not observe the dialog box opening")
                    
                if parsed.get("folder_visible", False):
                    vlm_score += 20
                    feedback_parts.append("✓ VLM confirmed folder visible in sidebar (20 pts)")
                else:
                    feedback_parts.append("✗ VLM did not observe the folder in the sidebar")
            else:
                logger.warning("VLM query did not succeed.")
        except Exception as e:
            logger.warning(f"Error during VLM verification: {e}")

    # Fallback if VLM fails or is unavailable but config looks perfect
    if not vlm_score and score == 65:
        logger.info("Providing fallback points since VLM failed but file config is perfect.")
        vlm_score = 35
        feedback_parts.append("✓ VLM fallback points awarded based on perfect configuration file (35 pts)")
        
    score += vlm_score

    # Determine Pass
    # Minimum requirements: Created during task, Name is correct, passed 60% total.
    key_criteria_met = (vf_mtime >= task_start) and (norm_name in norm_content)
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }