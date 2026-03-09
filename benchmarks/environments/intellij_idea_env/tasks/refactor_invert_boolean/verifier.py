#!/usr/bin/env python3
"""Verifier for refactor_invert_boolean task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_invert_boolean(traj, env_info, task_info):
    """Verify that the boolean field was inverted correctly.

    Criteria:
    1. Tests passed (behavior preserved) (40 pts)
    2. Field 'invalid' removed from Order.java (10 pts)
    3. Field 'valid' added to Order.java (10 pts)
    4. Method 'isInvalid' removed (10 pts)
    5. Method 'isValid' added (10 pts)
    6. Usages in OrderService updated (no isInvalid calls) (10 pts)
    7. VLM: Confirms usage of IDE/Refactoring tools (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Load result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # --- Criterion 1: Tests Passed (40 pts) ---
    if result.get("tests_passed", False):
        score += 40
        feedback_parts.append("Tests passed (logic preserved)")
    else:
        feedback_parts.append("Tests FAILED (logic broken)")

    # --- Structural Checks on Order.java (40 pts total) ---
    order_content = result.get("order_content", "")
    if not order_content:
        feedback_parts.append("Order.java content missing")
    else:
        # Check field renaming
        has_invalid_field = bool(re.search(r'private\s+boolean\s+invalid\s*;', order_content))
        has_valid_field = bool(re.search(r'private\s+boolean\s+valid\s*;', order_content))
        
        # Check method renaming
        has_isInvalid = "isInvalid(" in order_content
        has_isValid = "isValid(" in order_content

        if not has_invalid_field:
            score += 10
            feedback_parts.append("Field 'invalid' removed")
        else:
            feedback_parts.append("Field 'invalid' still present")

        if has_valid_field:
            score += 10
            feedback_parts.append("Field 'valid' present")
        else:
            feedback_parts.append("Field 'valid' missing")

        if not has_isInvalid:
            score += 10
            feedback_parts.append("Method 'isInvalid' removed")
        else:
            feedback_parts.append("Method 'isInvalid' still present")

        if has_isValid:
            score += 10
            feedback_parts.append("Method 'isValid' present")
        else:
            feedback_parts.append("Method 'isValid' missing")

    # --- Check Usages in Service (10 pts) ---
    service_content = result.get("service_content", "")
    if service_content:
        if "isInvalid(" not in service_content:
            score += 10
            feedback_parts.append("Usages updated in OrderService")
        else:
            feedback_parts.append("OrderService still calls isInvalid()")
            
    # --- VLM Verification (10 pts) ---
    # Use VLM to check if the user actually used the IDE refactoring dialog
    # or just manually edited files (which is more error-prone).
    # We look at trajectory frames.
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames
        
        # We need the VLM query function
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, num_samples=5)
            
            prompt = """
            Analyze these screenshots of a user working in IntelliJ IDEA.
            The task was to refactor a boolean field ("Invert Boolean").
            
            Look for:
            1. The "Invert Boolean" dialog box (title usually "Invert Boolean").
            2. The "Refactor" context menu being open.
            3. The "Rename" dialog.
            
            Did the user use any IDE refactoring tools/dialogs?
            Respond YES if you see any refactoring dialogs or menus.
            Respond NO if it looks like they just typed code manually.
            """
            
            vlm_result = query_vlm(images=frames, prompt=prompt)
            
            if vlm_result and vlm_result.get('success'):
                response = vlm_result.get('response', '').upper()
                if "YES" in response:
                    vlm_score = 10
                    feedback_parts.append("VLM: Refactoring tools usage detected")
                else:
                    # Fallback: if they got full points on structure, maybe they are just fast
                    # But we reserve these points for using the tool as requested
                    feedback_parts.append("VLM: No refactoring tools detected (manual edit?)")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # If VLM fails but task is otherwise perfect, give benefit of doubt if score > 80
        if score >= 80:
            vlm_score = 10
            feedback_parts.append("VLM skipped (awarded default)")

    score += vlm_score

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }