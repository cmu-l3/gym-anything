#!/usr/bin/env python3
"""
Verifier for bulk_reassign_leads_state task.

Criteria:
1. CA Leads Moved: All leads with state='CA' should be in list 9002.
2. Source Clean: No CA leads left in list 9001.
3. Precision: No non-CA leads moved to 9002.
4. Timing: Modifications happened during the task window.
5. VLM: Verification of UI interaction (bulk edit tool usage).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_reassign_leads_state(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Variables
    score = 0
    feedback_parts = []
    
    # Extract metrics
    ca_in_target = int(result.get("ca_in_target", 0))
    ca_in_source = int(result.get("ca_in_source", 0))
    non_ca_in_target = int(result.get("non_ca_in_target", 0))
    modified_during_task = result.get("modified_during_task", False)
    
    metadata = task_info.get("metadata", {})
    expected_ca_count = metadata.get("expected_ca_count", 2)

    # CRITERION 1: CA Leads Moved (40 pts)
    # Allow small variance if exact count isn't hardcoded in metadata, but strictly > 0
    if ca_in_target >= expected_ca_count:
        score += 40
        feedback_parts.append(f"Success: {ca_in_target} CA leads moved to target list.")
    elif ca_in_target > 0:
        # Partial credit if some were moved but maybe not all (unlikely in bulk move, but possible)
        score += 20
        feedback_parts.append(f"Partial: Only {ca_in_target}/{expected_ca_count} CA leads moved.")
    else:
        feedback_parts.append("Fail: No CA leads found in target list.")

    # CRITERION 2: Source Clean (20 pts)
    if ca_in_source == 0:
        score += 20
        feedback_parts.append("Success: No CA leads remain in source list.")
    else:
        feedback_parts.append(f"Fail: {ca_in_source} CA leads still remaining in source list.")

    # CRITERION 3: Precision (20 pts)
    if non_ca_in_target == 0:
        score += 20
        feedback_parts.append("Success: No incorrect states moved to target list.")
    else:
        feedback_parts.append(f"Fail: {non_ca_in_target} non-CA leads were incorrectly moved.")

    # CRITERION 4: Anti-Gaming / Timing (10 pts)
    if modified_during_task:
        score += 10
        feedback_parts.append("Success: Database modifications occurred during task.")
    else:
        feedback_parts.append("Fail: No modification timestamp update detected during task window.")

    # CRITERION 5: VLM Verification (10 pts)
    # Check for visual evidence of search or bulk edit
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = """
        Analyze these screenshots of a user interacting with Vicidial Admin.
        Look for:
        1. A "Lead Search" or "Leads" page.
        2. A search query involving "CA" or "California".
        3. A bulk modification screen (often yellow/warning background or "Modify Leads" header).
        4. A "Lists" or "Move" operation.

        Return valid JSON:
        {
            "search_visible": boolean,
            "bulk_edit_visible": boolean,
            "confidence": "low|medium|high"
        }
        """
        
        vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_response and vlm_response.get('success'):
            parsed = vlm_response.get('parsed', {})
            if parsed.get('search_visible') or parsed.get('bulk_edit_visible'):
                vlm_score = 10
                feedback_parts.append("VLM: Confirmed UI interaction.")
            else:
                feedback_parts.append("VLM: Could not confirm specific UI steps.")
        else:
            # Fallback if VLM fails, grant half points if DB checks pass
            if score >= 60: 
                vlm_score = 5
                feedback_parts.append("VLM: Skipped (API issue), fallback credit.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Graceful fallback
        if score >= 60:
            vlm_score = 5
    
    score += vlm_score

    # Final Pass/Fail
    passed = score >= 80  # High threshold as defined in design
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }