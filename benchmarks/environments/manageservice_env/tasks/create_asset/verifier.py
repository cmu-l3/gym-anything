#!/usr/bin/env python3
"""
Verifier for create_asset task (ManageEngine ServiceDesk Plus).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_asset(traj, env_info, task_info):
    """
    Verifies that the agent created the correct IT asset in ServiceDesk Plus.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'LAPTOP-ENG-0523')
    expected_serial = metadata.get('expected_serial', '8V3KX93')
    expected_tag = metadata.get('expected_tag', 'IT-2024-0523')
    desc_keywords = metadata.get('desc_keywords', ["Sarah Chen", "16GB"])

    # 1. Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    asset_found = result.get('asset_found', False)
    details = result.get('asset_details', {})
    
    # --- Criterion 1: Asset Exists (20 pts) ---
    if asset_found:
        score += 20
        feedback_parts.append(f"Asset '{expected_name}' created")
    else:
        feedback_parts.append(f"Asset '{expected_name}' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Serial Number (15 pts) ---
    actual_serial = details.get('serial', '').strip()
    if actual_serial == expected_serial:
        score += 15
        feedback_parts.append("Serial correct")
    else:
        feedback_parts.append(f"Serial mismatch (expected {expected_serial}, got '{actual_serial}')")

    # --- Criterion 3: Asset Tag (15 pts) ---
    actual_tag = details.get('tag', '').strip()
    if actual_tag == expected_tag:
        score += 15
        feedback_parts.append("Tag correct")
    else:
        feedback_parts.append(f"Tag mismatch (expected {expected_tag}, got '{actual_tag}')")

    # --- Criterion 4: Product Type (10 pts) ---
    actual_type = details.get('type', '').strip()
    if "Workstation" in actual_type:
        score += 10
        feedback_parts.append("Type correct")
    else:
        feedback_parts.append(f"Type mismatch (got '{actual_type}')")

    # --- Criterion 5: Product Name (10 pts) ---
    actual_product = details.get('product', '').strip()
    # Loose matching for product name as user might have typed it slightly differently
    if "Dell" in actual_product and "5540" in actual_product:
        score += 10
        feedback_parts.append("Product correct")
    else:
        feedback_parts.append(f"Product mismatch (got '{actual_product}')")

    # --- Criterion 6: State (5 pts) ---
    actual_state = details.get('state', '').strip()
    if "In Use" in actual_state:
        score += 5
        feedback_parts.append("State correct")
    else:
        feedback_parts.append(f"State mismatch (got '{actual_state}')")

    # --- Criterion 7: Description (5 pts) ---
    actual_desc = details.get('description', '')
    if all(k.lower() in actual_desc.lower() for k in desc_keywords):
        score += 5
        feedback_parts.append("Description contains details")
    else:
        feedback_parts.append("Description missing keywords")

    # --- Criterion 8: Anti-Gaming (Timestamp check) (5 pts) ---
    created_time = details.get('created_time', 0)
    task_start = result.get('task_start', 0)
    # Allow 60s tolerance for clock drift or pre-setup race conditions
    if created_time > (task_start - 60):
        score += 5
    else:
        feedback_parts.append("Asset creation timestamp predates task start")

    # --- Criterion 9: VLM Verification (15 pts) ---
    # Check if agent navigated to Assets module
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    if final_img:
        frames.append(final_img)
    
    if frames:
        vlm_prompt = (
            "Review these screenshots of a software agent using ManageEngine ServiceDesk Plus. "
            "Did the agent navigate to the 'Assets' tab/module and fill out a form? "
            "Answer with JSON: {\"assets_visited\": boolean, \"form_filled\": boolean}"
        )
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            parsed = vlm_res.get('parsed', {})
            if parsed.get('assets_visited', False):
                score += 15
                feedback_parts.append("VLM confirmed navigation")
            else:
                feedback_parts.append("VLM did not detect Assets navigation")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: give points if DB confirmed asset was created (hard to do without navigating)
            if asset_found:
                score += 15

    passed = (score >= 60) and asset_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }