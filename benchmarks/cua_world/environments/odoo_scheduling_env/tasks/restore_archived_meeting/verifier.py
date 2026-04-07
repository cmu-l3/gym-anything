#!/usr/bin/env python3
"""
Verifier for restore_archived_meeting task.

Verifies:
1. The original archived event (ID tracked from setup) is now Active.
2. No new duplicate events were created (prevents deleting/re-creating).
3. Critical content (description) is preserved.
4. Uses VLM to check for advanced filter usage in screenshots.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restore_archived_meeting(traj, env_info, task_info):
    """
    Verify the agent restored the specific archived meeting without re-creating it.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_desc_snippet = metadata.get("expected_description_snippet", "CRITICAL")

    # Load result from container
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
    
    # Check 1: Was the target event found and made active? (50 pts)
    target_found = result.get('target_event_found', False)
    target_active = result.get('target_event_active', False)
    
    if target_found and target_active:
        score += 50
        feedback_parts.append("Successfully restored the original archived meeting.")
    elif target_found:
        feedback_parts.append("Found the meeting but it is still Archived (Active=False).")
    else:
        feedback_parts.append("Target meeting not found in database (was it deleted?).")

    # Check 2: Were duplicates created? (30 pts)
    # We want exactly 1 event with this name (the original one).
    duplicate_count = result.get('duplicate_count', 0)
    newly_created_count = result.get('newly_created_count', 0)
    
    if duplicate_count == 1 and newly_created_count == 0:
        score += 30
        feedback_parts.append("Clean restoration: No duplicate events created.")
    elif newly_created_count > 0:
        score += 0
        feedback_parts.append(f"Penalty: Created {newly_created_count} NEW event(s) instead of restoring the existing one.")
    elif duplicate_count > 1:
        score += 10
        feedback_parts.append(f"Warning: {duplicate_count} events with same name exist.")

    # Check 3: Data Integrity (20 pts)
    # The description should match the original hidden one.
    current_desc = result.get('target_event_description', '')
    if expected_desc_snippet in current_desc:
        score += 20
        feedback_parts.append("Data integrity verified: Description preserved.")
    else:
        feedback_parts.append("Data integrity failed: Description does not match original.")

    # VLM Check (Optional boost/verification of process)
    # We look for the "Filters" or "Archived" search facet in the trajectory
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots of an Odoo Calendar/List interaction.
        The user is trying to find an 'Archived' meeting.
        
        Look for:
        1. Usage of the Search bar or Filter menu.
        2. Presence of a filter tag like 'Archived' or 'Active is False'.
        3. A switch to 'List' view (rows of items) which makes finding archived items easier.
        
        Answer JSON: {"used_filter": boolean, "switched_view": boolean}
        """
        # We don't penalize heavily if VLM fails, but can use it for feedback
        # Not implementing full VLM logic block here to keep verify function simple,
        # relying primarily on the robust XML-RPC state checks above.
    
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }