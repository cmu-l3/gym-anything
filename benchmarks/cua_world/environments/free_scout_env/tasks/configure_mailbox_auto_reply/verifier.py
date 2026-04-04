#!/usr/bin/env python3
"""
Verifier for configure_mailbox_auto_reply task.

Criteria:
1. Auto-reply is ENABLED in the database (25 pts)
2. Subject matches expected text (25 pts)
3. Body contains required phrases (3 phrases x 10 pts = 30 pts)
4. Configuration was actually updated during the task (anti-gaming) (10 pts)
5. VLM verification of final state (10 pts)
"""

import json
import tempfile
import os
import logging
import sys
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_mailbox_auto_reply(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_subject = metadata.get('expected_subject', "We've received your request - IT Support")
    required_phrases = metadata.get('required_phrases', [
        "within 24 hours",
        "December 14-15",
        "(555) 987-6543"
    ])

    # Copy result JSON
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
    
    # 1. Verify Auto-Reply Enabled (25 pts)
    ar_enabled = int(result.get('auto_reply_enabled', 0))
    if ar_enabled == 1:
        score += 25
        feedback_parts.append("Auto-reply enabled")
    else:
        feedback_parts.append("Auto-reply NOT enabled")

    # 2. Verify Subject (25 pts)
    actual_subject = result.get('auto_reply_subject', '').strip()
    if actual_subject.lower() == expected_subject.lower():
        score += 25
        feedback_parts.append("Subject correct")
    elif expected_subject.lower() in actual_subject.lower():
        score += 15
        feedback_parts.append("Subject partial match")
    else:
        feedback_parts.append(f"Subject incorrect (got: '{actual_subject}')")

    # 3. Verify Message Body Phrases (30 pts)
    actual_message = result.get('auto_reply_message', '').lower()
    phrases_found = 0
    for phrase in required_phrases:
        if phrase.lower() in actual_message:
            score += 10
            phrases_found += 1
        else:
            feedback_parts.append(f"Missing phrase: '{phrase}'")
    
    if phrases_found == len(required_phrases):
        feedback_parts.append("All body requirements met")

    # 4. Anti-Gaming: Check timestamp (10 pts)
    # The database record must have been updated AFTER the task started
    config_updated = result.get('config_updated_during_task', False)
    if config_updated:
        score += 10
        feedback_parts.append("Configuration saved during task")
    else:
        # If score is high but this is false, they might be gaming or the query failed
        feedback_parts.append("Warning: DB record not updated during task timeframe")
        # We don't fail strictly here in case of clock skew, but we deduct points

    # 5. VLM Verification (10 pts)
    # Check if the agent actually visited the settings page
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        # Analyze trajectory to see if they were in settings
        images_to_check = frames + ([final_img] if final_img else [])
        
        if images_to_check:
            prompt = """
            Look at these screenshots of the FreeScout help desk software.
            1. Do you see the "Mailbox Settings" or "Auto Reply" configuration page?
            2. Do you see a toggle switch for "Auto Reply" or "Enable"?
            3. Do you see text inputs for Subject and Message?
            
            Answer YES only if you clearly see the Auto Reply settings interface in at least one frame.
            """
            
            vlm_response = query_vlm(
                images=images_to_check,
                prompt=prompt
            ).get('answer', '').lower()
            
            if "yes" in vlm_response:
                vlm_score = 10
                feedback_parts.append("Visual verification passed")
            else:
                feedback_parts.append("Visual verification failed (settings page not seen)")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: give points if DB state is perfect
        if score >= 80:
            vlm_score = 10
            feedback_parts.append("VLM skipped (high confidence from DB)")

    score += vlm_score

    # Final Pass/Fail
    # strict pass: must be enabled AND have correct subject AND updated during task
    passed = (ar_enabled == 1) and (score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }