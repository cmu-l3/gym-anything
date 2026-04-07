#!/usr/bin/env python3
"""
Verifier for reassign_primary_provider task.

Verifies that the patient (Timothy Fey) is now assigned to Dr. James Carter (ID 2).
Primary Signal: Database check of `demographics_relate` table.
Secondary Signal: VLM check of the final screen to ensure UI reflects the change.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reassign_primary_provider(traj, env_info, task_info):
    """
    Verify patient provider reassignment.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    target_id = task_info.get('metadata', {}).get('target_provider_id', 2)
    old_id = task_info.get('metadata', {}).get('old_provider_id', 1)

    # 1. Retrieve JSON result from container
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
    
    # 2. Database Verification (Primary)
    has_target = result.get('has_target_provider', False)
    has_old = result.get('has_old_provider', False)
    
    # Ideally, target should be present (50 pts)
    if has_target:
        score += 50
        feedback_parts.append("Database confirms Dr. Carter is assigned.")
    else:
        feedback_parts.append("Database: Dr. Carter (ID 2) NOT found in patient relations.")

    # Ideally, old provider should be removed (25 pts)
    # Note: NOSH might allow multiple, but usually "Primary" implies a switch or at least the new one is added.
    # If the agent just added Carter without removing Admin, that's partial credit, but usually reassignment implies replacement.
    # We'll award points if the new one is there. If the old one is gone, bonus points for cleanliness.
    if not has_old:
        score += 25
        feedback_parts.append("Old provider (Dr. Admin) removed.")
    elif has_target and has_old:
        # If both exist, maybe partial credit? Or maybe that's acceptable behavior in this EHR.
        # We'll give 10 points for safety.
        score += 10
        feedback_parts.append("Old provider still linked (multiple providers?).")

    # 3. VLM Verification (Secondary - 25 pts)
    # Check if UI shows "James Carter" or "Carter" in the header/demographics area.
    final_screenshot = get_final_screenshot(traj)
    vlm_passed = False
    
    if final_screenshot and has_target: # Only check VLM if DB passed to save tokens/time
        prompt = """
        Review this EHR screenshot for patient Timothy Fey.
        Check the 'Provider' or 'Care Team' section.
        Does it show 'James Carter' or 'Carter' as the provider?
        Respond JSON: {"provider_visible": bool, "provider_name_found": "str"}
        """
        try:
            vlm_response = query_vlm(image=final_screenshot, prompt=prompt)
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("provider_visible"):
                    score += 25
                    vlm_passed = True
                    feedback_parts.append("VLM confirms 'James Carter' visible in UI.")
                else:
                    feedback_parts.append("VLM did not clearly see 'James Carter' in the UI.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Pass logic
    # Must have database confirmation of target.
    passed = has_target and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }