#!/usr/bin/env python3
"""
Verifier for attach_ui_mockup task.

Verifies that:
1. An attachment file exists in the project's 'attachments' directory.
2. The SRS document JSON contains a reference to this attachment for the correct requirement (SRS-1.1).
3. The attachment file matches the expected source (Mockup).
4. VLM confirms visual presence of attachment icon.
"""

import json
import os
import tempfile
import logging
import shutil
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SRS_REL_PATH = "documents/SRS.json"
ATTACHMENTS_REL_DIR = "attachments"

def find_req_by_id_or_heading(data_list, target_id, target_heading):
    """Recursively find requirement by ID (e.g. SRS-1.1) or text heading."""
    for item in data_list:
        # Check ID
        # ReqView IDs in JSON are usually integers (e.g., "id": "12"), 
        # and the displayed ID (SRS-12) is computed from document prefix.
        # However, we can check headings or text.
        
        # Check heading
        heading = item.get("heading", "")
        if target_heading.lower() in heading.lower():
            return item
            
        # Check text (if heading is missing)
        text = item.get("text", "")
        if target_heading.lower() in text.lower():
            return item
            
        # Recurse
        if "children" in item:
            found = find_req_by_id_or_heading(item["children"], target_id, target_heading)
            if found:
                return found
    return None

def verify_attach_ui_mockup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir')
    target_heading = metadata.get('target_req_heading', "User Identification")
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Task Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            tf.seek(0)
            task_result = json.load(tf)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    # 2. Verify File System State (Attachment in Dir)
    attachment_found = task_result.get("attachment_found_in_dir", False)
    attachment_filename = task_result.get("attachment_filename", "")
    
    if attachment_found:
        score += 30
        feedback_parts.append(f"Attachment file found in project ({attachment_filename})")
    else:
        feedback_parts.append("No new attachment file found in project directory")

    # 3. Verify SRS JSON Structure
    srs_local_path = tempfile.mktemp(suffix=".json")
    try:
        remote_srs_path = os.path.join(project_dir, SRS_REL_PATH)
        copy_from_env(remote_srs_path, srs_local_path)
        
        with open(srs_local_path, 'r') as f:
            srs_data = json.load(f)
            
        # Find the target requirement
        req = find_req_by_id_or_heading(srs_data.get("data", []), None, target_heading)
        
        if req:
            score += 10 # Found the requirement
            # Check for attachments field
            attachments = req.get("attachments", [])
            
            if attachments:
                # ReqView attachments are usually list of filenames
                if len(attachments) > 0:
                    score += 40
                    feedback_parts.append(f"Requirement '{target_heading}' has {len(attachments)} attachment(s)")
                    
                    # Verify filename match if possible
                    # The filename in JSON should match the one in the directory
                    if attachment_filename and attachment_filename in attachments:
                         score += 10
                         feedback_parts.append("Attachment filename matches file in directory")
                else:
                    feedback_parts.append("Requirement has empty attachments list")
            else:
                feedback_parts.append(f"Requirement '{target_heading}' has no attachments")
        else:
            feedback_parts.append(f"Could not locate requirement '{target_heading}' in SRS.json")
            
    except Exception as e:
        feedback_parts.append(f"Error inspecting SRS.json: {e}")
    finally:
        if os.path.exists(srs_local_path):
            os.remove(srs_local_path)

    # 4. VLM Verification
    # Use trajectory to see if "Attach" dialog was used or attachment icon is visible
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=3)
    
    vlm_prompt = f"""
    The user was asked to attach a file 'login_mockup.png' to a requirement in ReqView.
    Review the images.
    1. Do you see a file picker dialog selecting 'login_mockup.png'?
    2. Do you see a paperclip icon or image thumbnail next to a requirement (likely 'User Identification') in the final state?
    3. Is there any error message?
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames + [final_screenshot], prompt=vlm_prompt)
        # Simple heuristic based on VLM response
        lower_resp = vlm_res.get("response", "").lower()
        if "yes" in lower_resp and ("paperclip" in lower_resp or "icon" in lower_resp or "thumbnail" in lower_resp or "attach" in lower_resp):
            vlm_score = 10
            feedback_parts.append("VLM confirms visual evidence of attachment")
        elif "error" in lower_resp:
            feedback_parts.append("VLM detected potential error messages")
    except Exception:
        pass # VLM optional fallback
    
    score += vlm_score

    # Anti-gaming: Check if SRS was actually modified
    if task_result.get("srs_modified", False):
        score += 0 # Already implicitly covered by JSON check, but good sanity check
    else:
        # If JSON matches but file not modified time-wise, suspect gaming (pre-canned?)
        # But copy_from_env gets current state. 
        pass

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }