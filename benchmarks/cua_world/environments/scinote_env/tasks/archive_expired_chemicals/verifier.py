#!/usr/bin/env python3
"""
Verifier for archive_expired_chemicals task.

Verification Strategy:
1. Programmatic State Check: Reads exported JSON to verify exact archival status.
   - 3 specific expired items MUST be archived (20 points each).
   - 2 specific valid items MUST NOT be archived (20 points each).
2. VLM Trajectory Check: Verifies that the agent actually interacted with the UI
   to perform the archiving, preventing API or backend gaming.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """You are verifying an agent's trajectory for an electronic lab notebook task.
Task: Archive expired chemical reagents in the 'Chemical Storage' inventory.

Review the sequence of screenshots and determine:
1. Did the agent navigate to the Inventory / Repositories view?
2. Did the agent open the 'Chemical Storage' repository?
3. Did the agent select items and use an 'Archive' or 'Delete' function in the user interface?

Respond in JSON format:
{
    "navigated_to_inventory": true/false,
    "opened_chemical_storage": true/false,
    "used_archive_function": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""


def verify_archive_expired_chemicals(traj, env_info, task_info):
    """
    Verify that only the expired chemicals were archived.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    # 1. Retrieve and parse metadata
    metadata = task_info.get('metadata', {})
    items_to_archive = metadata.get('items_to_archive', ["Acetonitrile", "Methanol", "Chloroform"])
    items_to_keep = metadata.get('items_to_keep', ["Ethanol 96%", "Isopropanol"])

    # 2. Retrieve the exported JSON result from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/archive_chemicals_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if not result.get('success', False):
        error_msg = result.get('error', 'Unknown export error')
        return {"passed": False, "score": 0, "feedback": f"Setup/Export failed: {error_msg}"}

    db_items = result.get('items', [])
    
    score = 0
    feedback_parts = []
    
    # Check "Must Archive" items
    archived_correctly = 0
    for expected in items_to_archive:
        # Find the matching item from the DB
        matched = next((i for i in db_items if expected.lower() in i.get('name', '').lower()), None)
        if matched:
            if matched.get('archived', False):
                score += 20
                archived_correctly += 1
                feedback_parts.append(f"[PASS] Expired item '{expected}' is archived.")
            else:
                feedback_parts.append(f"[FAIL] Expired item '{expected}' is STILL ACTIVE.")
        else:
            feedback_parts.append(f"[ERROR] Item '{expected}' missing from database.")

    # Check "Must Keep" items
    kept_correctly = 0
    for expected in items_to_keep:
        matched = next((i for i in db_items if expected.lower() in i.get('name', '').lower()), None)
        if matched:
            if not matched.get('archived', False):
                score += 20
                kept_correctly += 1
                feedback_parts.append(f"[PASS] Valid item '{expected}' was kept active.")
            else:
                feedback_parts.append(f"[FAIL] Valid item '{expected}' was FALSELY ARCHIVED.")
        else:
            feedback_parts.append(f"[ERROR] Item '{expected}' missing from database.")

    # 3. VLM Trajectory Verification
    vlm_passed = False
    if query_vlm:
        try:
            # Sample frames from trajectory
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=6)
            
            if frames:
                vlm_res = query_vlm(images=frames, prompt=build_vlm_prompt())
                parsed = vlm_res.get("parsed", {})
                
                # Check if UI interactions indicate archival
                used_ui = (
                    parsed.get("navigated_to_inventory", False) and 
                    parsed.get("used_archive_function", False)
                )
                
                if used_ui:
                    vlm_passed = True
                    feedback_parts.append("[PASS] VLM verified UI archival interaction.")
                else:
                    feedback_parts.append("[WARN] VLM did not clearly see UI archival actions.")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append(f"[WARN] VLM verification error: {e}")

    # Ensure anti-gaming: Agent cannot pass simply by running a script if VLM proves no UI usage.
    # We heavily penalize the score if VLM confirms no UI action took place, but we allow 
    # programmatic passing if VLM is unavailable (fallback).
    if query_vlm and not vlm_passed:
        score = int(score * 0.5)
        feedback_parts.append("Penalty applied: VLM could not confirm UI usage.")

    # Pass threshold: 80 points (meaning at most 1 mistake, but if VLM fails it caps at 50 points)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "expired_items_archived": archived_correctly,
            "valid_items_kept": kept_correctly,
            "vlm_ui_verified": vlm_passed
        }
    }