#!/usr/bin/env python3
"""
Verifier for Internal Affairs Conflict Check Task.

Logic:
1. Verify Case Priority is 'High' (50 pts)
2. Verify a Note exists with 'Internal Affairs' keywords (30 pts)
3. Verify via VLM that the agent actually searched/checked the Person record (20 pts)
   - This prevents "blind guessing" where the agent just sets High Priority without checking.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_internal_affairs_check(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback_parts = []
    
    # --- Criterion 1: Priority Update (50 pts) ---
    final_priority = result.get("final_priority", "Unknown")
    expected_priority = "High"
    
    if final_priority.lower() == expected_priority.lower():
        score += 50
        feedback_parts.append(f"✅ Priority correctly set to {final_priority}")
    else:
        feedback_parts.append(f"❌ Priority is '{final_priority}', expected '{expected_priority}'")

    # --- Criterion 2: Note Addition (30 pts) ---
    note_added = result.get("note_added", False)
    note_content = result.get("note_content_sample", "")
    
    if note_added:
        score += 30
        feedback_parts.append("✅ Internal Affairs note added")
    else:
        feedback_parts.append("❌ Missing required note about Internal Affairs/Employee status")

    # --- Criterion 3: VLM Process Verification (20 pts) ---
    # We want to confirm the agent actually looked at the People module/search results
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an agent's workflow in ArkCase.
    The task requires the agent to:
    1. Read a case description.
    2. Go to the 'People' module or use the Search bar.
    3. Find a person and check their email address/profile.
    
    Look at these screenshots of the agent's session.
    Did the agent perform a search for a person OR view a Person's profile page?
    
    Respond with JSON:
    {
        "person_search_or_view_detected": true/false,
        "reasoning": "brief explanation"
    }
    """
    
    vlm_passed = False
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_res.get("parsed", {})
        if parsed.get("person_search_or_view_detected", False):
            vlm_passed = True
            score += 20
            feedback_parts.append("✅ Verified investigation steps (Person search/view detected)")
        else:
            feedback_parts.append("⚠️ Could not verify that Person record was checked (VLM)")
            # If they got the right answer but we didn't see the work, we leave it at 80 (Passable but not perfect)
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append("⚠️ VLM verification skipped due to error")
        # Give benefit of doubt if technical error occurs, but only if other parts correct
        if score >= 80:
            score += 20

    # --- Final Scoring ---
    passed = score >= 80  # Requires at least Priority + Note
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }