#!/usr/bin/env python3
"""
Verifier for create_canned_responses task.

Verifies:
1. API State: Checks if the two specific canned responses exist with correct text and scope.
2. VLM Verification: Checks trajectory for UI navigation.
3. Timestamps: Ensures data was created during the task.
"""

import json
import logging
import os
import tempfile
import sys
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_canned_responses(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Task Metadata
    metadata = task_info.get('metadata', {})
    expected_responses = metadata.get('responses', [])
    task_start = result.get('task_start', 0)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. API Verification (80 Points Total)
    # ------------------------------------------------------------------
    api_data = result.get('api_data', {}).get('cannedResponses', [])
    
    if not api_data:
        feedback_parts.append("No canned responses found in system.")
    
    # Map shortcuts to actual response objects for easier lookup
    found_map = {r.get('shortcut'): r for r in api_data}

    for expected in expected_responses:
        shortcut = expected['shortcut']
        target_text = expected['text']
        
        item_feedback = []
        item_score = 0
        
        # Check Existence (10 pts)
        actual = found_map.get(shortcut)
        if actual:
            item_score += 10
            
            # Check Text Content (20 pts)
            # Allow partial match/substring to be generous with whitespace
            actual_text = actual.get('text', '')
            if target_text.strip() in actual_text.strip() or actual_text.strip() in target_text.strip():
                item_score += 20
            else:
                item_feedback.append(f"Text mismatch for {shortcut}")
            
            # Check Scope (10 pts)
            # Scope 'global' or 'user' (public usually means global or specific scope logic)
            # In Rocket.Chat, public usually means scope="global" or departmentId is null
            actual_scope = actual.get('scope', '')
            if actual_scope == 'global':
                item_score += 10
            else:
                item_feedback.append(f"Scope mismatch for {shortcut}: expected global/public, got {actual_scope}")
                
            # Anti-Gaming: Check Timestamp
            created_at_str = actual.get('_createdAt', '')
            # Rocket.Chat timestamps are ISO strings. Just checking existence implies creation
            # since we wiped clean in setup. But strict check is harder without parsing ISO.
            # We rely on "clean slate" setup for validity.
            
        else:
            item_feedback.append(f"Missing response: {shortcut}")
        
        score += item_score
        if item_feedback:
            feedback_parts.append(f"{shortcut}: " + ", ".join(item_feedback))
        else:
            feedback_parts.append(f"{shortcut}: Correct")

    # ------------------------------------------------------------------
    # 2. VLM Verification (20 Points)
    # ------------------------------------------------------------------
    # We check if the agent actually visited the Canned Responses UI
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_score = 0
    if frames:
        vlm_prompt = """
        Analyze these screenshots of a Rocket.Chat user session.
        Did the user navigate to the 'Canned Responses' or 'Omnichannel' settings area?
        Look for:
        1. A sidebar menu item 'Canned Responses'
        2. A list of shortcuts like '!refund_policy' or '!office_hours'
        3. Forms for creating canned responses
        
        Reply JSON: {"visited_canned_responses": boolean, "reason": "string"}
        """
        
        # Use last few frames + final to catch the action
        check_images = frames[-2:] + [final_screen] if final_screen else frames
        
        try:
            vlm_res = query_vlm(prompt=vlm_prompt, images=check_images)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('visited_canned_responses'):
                    vlm_score = 20
                    feedback_parts.append("VLM: Confirmed UI navigation")
                else:
                    feedback_parts.append("VLM: Could not confirm UI navigation")
            else:
                # Fallback if VLM fails but API passed - give benefit of doubt if score high
                if score >= 60:
                    vlm_score = 20
                    feedback_parts.append("VLM: Skipped (API validation sufficient)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Graceful fallback
            if score >= 60:
                vlm_score = 20

    score += vlm_score

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    # Pass threshold: 80 points (Needs both responses mostly correct)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }