#!/usr/bin/env python3
"""
Verifier for configure_notification_sounds task.

Criteria:
1. Meeting Joined (URL check) - 20 pts
2. Display Name Correct (Redux store check) - 10 pts
3. "Participant Joined" Sound DISABLED - 15 pts
4. "Participant Left" Sound DISABLED - 15 pts
5. "Reaction Sounds" DISABLED - 15 pts
6. "Talk While Muted" Sound ENABLED - 15 pts
7. Agent Screenshot Exists - 10 pts

Total: 100 pts
Pass Threshold: 70 pts (Allows minor error, but requires core sound config)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_notification_sounds(traj, env_info, task_info):
    """
    Verify the notification sounds configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result from container
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
    
    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_room = metadata.get('room_name', 'InterpreterBooth42')
    expected_name = metadata.get('expected_display_name', 'Interpreter_ES')
    
    # 1. Verify Meeting Joined (20 pts)
    final_url = result.get('final_url', '')
    if expected_room.lower() in final_url.lower():
        score += 20
        feedback_parts.append("Joined correct meeting room (+20)")
    else:
        feedback_parts.append(f"Wrong room or not joined (URL: {final_url})")

    # 2. Verify Display Name (10 pts)
    settings = result.get('settings', {})
    # Display name might be in settings or profile, the export script dumps features/base/settings
    # which usually contains 'displayName' if set locally
    actual_name = settings.get('displayName', '')
    if actual_name == expected_name:
        score += 10
        feedback_parts.append("Display name correct (+10)")
    elif expected_name.lower() in str(actual_name).lower():
        score += 5
        feedback_parts.append(f"Display name partial match '{actual_name}' (+5)")
    else:
        feedback_parts.append(f"Display name incorrect ('{actual_name}')")

    # 3. Verify Sound Settings (15 pts each for disabled, 15 for enabled)
    # Keys from metadata: soundsParticipantJoined, soundsParticipantLeft, soundsReactions, soundsTalkWhileMuted
    # Note: Jitsi settings keys might default to undefined if never touched, or true/false.
    # Default is usually TRUE (sounds on). We want FALSE for the first 3.
    
    # Participant Joined -> Expect FALSE
    val_joined = settings.get('soundsParticipantJoined')
    if val_joined is False:
        score += 15
        feedback_parts.append("Participant Joined sound disabled (+15)")
    else:
        feedback_parts.append(f"Participant Joined sound incorrect ({val_joined})")

    # Participant Left -> Expect FALSE
    val_left = settings.get('soundsParticipantLeft')
    if val_left is False:
        score += 15
        feedback_parts.append("Participant Left sound disabled (+15)")
    else:
        feedback_parts.append(f"Participant Left sound incorrect ({val_left})")

    # Reactions -> Expect FALSE
    val_reactions = settings.get('soundsReactions')
    if val_reactions is False:
        score += 15
        feedback_parts.append("Reaction sounds disabled (+15)")
    else:
        feedback_parts.append(f"Reaction sounds incorrect ({val_reactions})")

    # Talk While Muted -> Expect TRUE
    # If key is missing, it usually defaults to TRUE, but task asked to ensure it's ON.
    # We accept True or None (default), but strictly it should be True if they interacted with it.
    # However, since we want to penalize "Disable All", we specifically check if it is NOT False.
    val_muted = settings.get('soundsTalkWhileMuted')
    if val_muted is not False: 
        score += 15
        feedback_parts.append("Talk While Muted sound enabled (+15)")
    else:
        feedback_parts.append("Talk While Muted sound disabled (incorrect)")

    # 4. Verify Agent Screenshot (10 pts)
    if result.get('agent_screenshot_exists', False):
        score += 10
        feedback_parts.append("Agent screenshot saved (+10)")
    else:
        feedback_parts.append("Agent screenshot missing")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
        "details": settings
    }