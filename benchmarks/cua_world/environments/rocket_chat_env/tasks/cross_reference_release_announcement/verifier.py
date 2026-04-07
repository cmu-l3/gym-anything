#!/usr/bin/env python3
"""
Verifier for cross_reference_release_announcement task.
Ensures the agent navigated to the releases channel, extracted the permalink
for the specifically requested newest release, and pasted it into the general channel.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cross_reference_release_announcement(traj, env_info, task_info):
    # Retrieve execution copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract JSON data from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    task_start = result.get("task_start", 0)
    target_msg_id = result.get("target_msg_id", "")
    general_messages = result.get("general_messages", [])

    if not target_msg_id:
        return {"passed": False, "score": 0, "feedback": "System Error: Could not identify target_msg_id from seed manifest."}

    score = 0
    feedback_parts = []
    message_found = False
    format_correct = False
    target_linked = False

    # Programmatic Assessment: Check messages in #general
    for msg in general_messages:
        # Check Timestamp (ISO format like "2026-02-16T12:00:00.000Z")
        msg_ts_str = msg.get("ts", "")
        try:
            clean_ts = msg_ts_str.split('.')[0]
            msg_time = datetime.strptime(clean_ts, "%Y-%m-%dT%H:%M:%S").timestamp()
        except Exception:
            msg_time = task_start + 1  # Fallback gracefully if parsing fails

        # Anti-gaming: Ensure the message was sent *during* the task
        if msg_time < task_start:
            continue

        text = msg.get("msg", "")

        # Check expected pattern
        if "Latest release notes:" in text:
            message_found = True
            
            # General Permalinks format contains "?msg="
            if "?msg=" in text:
                format_correct = True
            
            # The agent MUST link to the exact target release
            if target_msg_id in text:
                target_linked = True
                break  # Stop searching, found the correct post!

    # Determine programmatic score
    if message_found:
        score += 20
        feedback_parts.append("Message posted in #general")
        
        if format_correct:
            score += 20
            feedback_parts.append("URL format is a valid permalink")
            
            if target_linked:
                score += 60
                feedback_parts.append("Correct target release linked!")
            else:
                feedback_parts.append("Failed: Linked to WRONG message (not the newest release)")
        else:
            feedback_parts.append("Failed: Message text did not include a permalink URL in expected format")
    else:
        feedback_parts.append("Failed: No message found in #general starting with 'Latest release notes:'")

    # VLM Trajectory check: Additional layer of evidence
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """Analyze these sequential screenshots of a user operating Rocket.Chat.
        Assess if the user navigated to the '#release-updates' channel to look for information, and then navigated to the '#general' channel to paste it.
        Respond with exactly this JSON:
        {"visited_release_updates": true/false, "visited_general": true/false}"""
        
        vlm_res = query_vlm(images=images, prompt=prompt)
        if vlm_res and vlm_res.get("parsed"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("visited_release_updates") and parsed.get("visited_general"):
                feedback_parts.append("VLM visual verification confirmed cross-channel navigation")
            else:
                feedback_parts.append("VLM visual verification did not observe cross-channel navigation")
    except ImportError:
        logger.warning("VLM libraries not available for trajectory verification.")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    # Set passing condition
    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }