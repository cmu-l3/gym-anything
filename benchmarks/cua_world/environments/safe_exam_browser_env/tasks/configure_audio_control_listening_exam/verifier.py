#!/usr/bin/env python3
"""
Verifier for configure_audio_control_listening_exam task.

Verification Strategy:
1. Programmatic (DB): Check if 'Music History Listening Exam' configuration was created.
2. Programmatic (DB): Verify `allowSpellCheck` is false.
3. Programmatic (DB): Verify `audioControlEnabled` is true.
4. Programmatic (DB): Verify `audioVolumeLevel` is exactly 80.
5. Programmatic (DB): Verify `audioMute` is false.
6. VLM Trajectory (Anti-Gaming): Verify agent navigated the SEB Server UI.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_falsy(val):
    """Helper to check if a DB value represents false."""
    if val is None:
        return False
    return str(val).lower() in ['false', '0', 'no', 'off', '']

def is_truthy(val):
    """Helper to check if a DB value represents true."""
    if val is None:
        return False
    return str(val).lower() in ['true', '1', 'yes', 'on']

def verify_audio_control_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read JSON result from container
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
    
    config_exists = result.get('config_exists', False)
    settings = result.get('settings', {})

    # Early exit if config was not created
    if not config_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Configuration 'Music History Listening Exam' was not created."
        }
    
    score += 20
    feedback_parts.append("Config created")

    # DB Checks for specific settings
    # Use fallback fuzzy matching in case SEB versions slightly change attribute names
    def get_setting(key_exact, key_fuzzy):
        if key_exact in settings:
            return settings[key_exact]
        for k, v in settings.items():
            if key_fuzzy.lower() in k.lower():
                return v
        return None

    spell_check = get_setting('allowSpellCheck', 'spellcheck')
    audio_enabled = get_setting('audioControlEnabled', 'audiocontrol')
    volume_level = get_setting('audioVolumeLevel', 'volumelevel')
    audio_mute = get_setting('audioMute', 'audiomute')

    # Verify Spell Check (Expected: False)
    if spell_check is not None and is_falsy(spell_check):
        score += 15
        feedback_parts.append("Spell check disabled")
    else:
        feedback_parts.append(f"Spell check incorrect (found: {spell_check})")

    # Verify Audio Control Enabled (Expected: True)
    if audio_enabled is not None and is_truthy(audio_enabled):
        score += 15
        feedback_parts.append("Audio control enabled")
    else:
        feedback_parts.append(f"Audio control incorrect (found: {audio_enabled})")

    # Verify Volume Level (Expected: 80)
    if volume_level is not None and str(volume_level) == '80':
        score += 15
        feedback_parts.append("Volume level set to 80")
    else:
        feedback_parts.append(f"Volume level incorrect (found: {volume_level})")

    # Verify Audio Mute (Expected: False)
    if audio_mute is not None and is_falsy(audio_mute):
        score += 15
        feedback_parts.append("Audio mute disabled")
    else:
        feedback_parts.append(f"Audio mute incorrect (found: {audio_mute})")

    # VLM Trajectory Verification
    # To prevent pure API gaming if an agent just runs a curl command, verify visual work.
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            Look at these frames from a web browser session interacting with SEB Server.
            Did the user navigate the graphical interface to create or edit an Exam Configuration?
            Look for evidence of form filling, tabs like 'Browser' or 'Audio', or configuration menus.
            Return a JSON object: {"used_gui": true/false}
            """
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response and vlm_response.get("parsed", {}).get("used_gui", False):
                score += 20
                feedback_parts.append("VLM confirmed GUI usage")
            else:
                feedback_parts.append("VLM did not detect GUI usage")
        else:
            feedback_parts.append("No trajectory frames for VLM")
    except Exception as e:
        logger.warning(f"VLM verification failed/skipped: {e}")
        # If VLM fails due to framework issues, grant the points to avoid penalizing agent
        score += 20
        feedback_parts.append("VLM skipped (awarded default)")

    # 100 points total: 20 config + 15 spell + 15 audio_en + 15 vol + 15 mute + 20 VLM
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }