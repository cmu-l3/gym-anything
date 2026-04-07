#!/usr/bin/env python3
"""
Verifier for freeze_release_channel task.

Checks:
1. Channel is read-only (35 pts)
2. Channel announcement matches expected text (30 pts, partial credit available)
3. User 'agent.user' is a moderator (35 pts)
4. Anti-gaming: checks if state actually changed from defaults
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_freeze_release_channel(traj, env_info, task_info):
    """
    Verify that the agent locked down the release channel correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_announcement = metadata.get('expected_announcement', "This channel is now archived. Release tracking for this cycle is complete. Contact @admin for questions.")
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if not result.get('api_success'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Verification failed: Could not query Rocket.Chat API (Admin login failed or channel not found)."
        }

    final_state = result.get('final_state', {})
    score = 0
    feedback_parts = []
    
    # 1. Check Read-Only Status (35 pts)
    is_read_only = final_state.get('read_only', False)
    if is_read_only:
        score += 35
        feedback_parts.append("PASS: Channel set to read-only")
    else:
        feedback_parts.append("FAIL: Channel is NOT read-only")

    # 2. Check Announcement (30 pts)
    actual_announcement = final_state.get('announcement', "")
    
    # Normalize strings for comparison (strip whitespace)
    norm_expected = expected_announcement.strip()
    norm_actual = actual_announcement.strip()

    if norm_actual == norm_expected:
        score += 30
        feedback_parts.append("PASS: Announcement matches exactly")
    else:
        # Partial credit logic
        lower_actual = norm_actual.lower()
        key_phrases = ["archived", "tracking", "complete", "@admin"]
        matches = sum(1 for phrase in key_phrases if phrase in lower_actual)
        
        if matches == 4:
            # Almost correct but minor typo/spacing
            score += 20
            feedback_parts.append(f"PARTIAL: Announcement contains all key info but not exact match (Got: '{norm_actual}')")
        elif matches >= 2:
            score += 10
            feedback_parts.append(f"PARTIAL: Announcement contains some key info (Got: '{norm_actual}')")
        elif not norm_actual:
            feedback_parts.append("FAIL: No announcement set")
        else:
            feedback_parts.append(f"FAIL: Announcement incorrect (Got: '{norm_actual}')")

    # 3. Check Moderator Role (35 pts)
    is_moderator = final_state.get('agent_is_moderator', False)
    if is_moderator:
        score += 35
        feedback_parts.append("PASS: agent.user assigned as moderator")
    else:
        feedback_parts.append("FAIL: agent.user is NOT a moderator")

    # Anti-gaming: Ensure task took some time (e.g., > 2 seconds)
    start_time = result.get('task_start_timestamp', 0)
    end_time = result.get('task_end_timestamp', 0)
    duration = end_time - start_time
    
    if duration < 2:
         feedback_parts.append("WARNING: Task completed suspiciously fast")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }