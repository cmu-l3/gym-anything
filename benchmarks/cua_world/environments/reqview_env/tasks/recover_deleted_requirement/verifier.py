#!/usr/bin/env python3
"""Verifier for recover_deleted_requirement task.

Checks that requirement SRS-6 has been restored to the SRS document structure.

Verification Strategy:
1. Parse the SRS.json file from the project directory.
2. Recursively search the 'children' tree for an object with id="SRS-6" (or integer id matching SRS-6).
3. Verify the text matches the expected original text (anti-gaming: ensures they didn't just create a new req named SRS-6).
4. Verify the ID is exactly what was lost (creating a new req usually assigns a new sequential ID).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _find_req_recursive(items, target_id_suffix):
    """
    Recursively find a requirement by ID.
    ReqView IDs in JSON are usually integers (e.g. 6), but displayed as SRS-6.
    We check if the JSON 'id' matches the target integer.
    """
    target_int = int(target_id_suffix)
    
    for item in items:
        # Check current item
        # ID in JSON is typically an integer
        current_id = item.get('id')
        if current_id == target_int or str(current_id) == str(target_id_suffix):
            return item
        
        # Recurse children
        if 'children' in item:
            found = _find_req_recursive(item['children'], target_id_suffix)
            if found:
                return found
    return None

def verify_recover_deleted_requirement(traj, env_info, task_info):
    """Verify SRS-6 was restored."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    project_path = metadata.get('project_path', '/home/ga/Documents/ReqView/RecoverTask_project')
    srs_rel_path = metadata.get('srs_relative_path', 'documents/SRS.json')
    target_id_full = metadata.get('target_id', 'SRS-6')
    target_text_sub = metadata.get('target_text_substring', 'authenticate Users')

    # Extract integer ID (SRS-6 -> 6)
    target_id_suffix = target_id_full.split('-')[-1] if '-' in target_id_full else target_id_full

    # Construct full path to SRS.json
    srs_json_path = os.path.join(project_path, srs_rel_path)

    # Copy SRS.json from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(srs_json_path, tmp.name)
        with open(tmp.name) as f:
            srs_data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve project data. The project might not have been saved. Error: {e}"
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    
    # 1. Primary Verification: Check if ID exists in active document (60 pts)
    # The 'data' field usually contains the list of top-level requirements
    root_items = srs_data.get('data', [])
    found_req = _find_req_recursive(root_items, target_id_suffix)

    if found_req:
        score += 60
        feedback_parts.append(f"Requirement {target_id_full} found in document structure")
        
        # 2. Integrity Verification: Check text content (20 pts)
        # ReqView text is HTML, so we check substring
        actual_text = found_req.get('text', '')
        if target_text_sub in actual_text:
            score += 20
            feedback_parts.append("Content matches original requirement")
        else:
            feedback_parts.append(f"Content mismatch (Expected substring '{target_text_sub}' not found)")
            
        # 3. Status Verification (20 pts)
        # Ensure it's not marked as deleted (though if it's in the main tree, it shouldn't be)
        if not found_req.get('deleted', False):
            score += 20
            feedback_parts.append("Status is active (not deleted)")
        else:
            feedback_parts.append("Item exists but is marked 'deleted'")
    else:
        feedback_parts.append(f"Requirement {target_id_full} NOT found in active document")

    # 4. Secondary Verification: VLM Trajectory Check (Tie-breaker/Safety)
    # If file check failed (maybe they didn't save?), check if they used the UI correctly.
    # If file check passed, we just use this to confirm the method.
    passed = score >= 80

    if not passed:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_result = query_vlm(
            images=frames,
            prompt="Is the user interacting with a 'Deleted Objects' or 'Undelete' dialog in this software? Do you see a list of deleted items being accessed?"
        )
        if vlm_result.get('parsed', {}).get('answer', False) is True:
            feedback_parts.append("(VLM observed correct workflow interaction, but changes were not saved/persisted)")
            # We don't award points for unsaved work in a data recovery task, but good feedback.

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "target_id": target_id_full,
            "found": bool(found_req)
        }
    }