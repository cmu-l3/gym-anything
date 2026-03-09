#!/usr/bin/env python3
"""
Verifier for customize_notification_sound task.

Verifies that the notification sound for Flight Crew View was changed from
default to a sound starting with 'C' (e.g., Chime, Carbon).

Verification Strategy:
1. Parse the 'dumpsys notification' output captured from the device.
2. Extract the 'sound' URI/Field for the notification channel.
3. Compare Initial vs Final state to ensure a change occurred.
4. Verify the new sound meets the criteria (starts with 'C' or is not default).
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_dumpsys_notification(content):
    """
    Parses relevant info from `dumpsys notification` output for the specific package.
    Returns a dict of channel_id -> sound_uri.
    """
    channels = {}
    current_channel = None
    
    # Simple state machine to parse the indented structure of dumpsys
    # Example structure:
    #   Channel{id='miscellaneous', name='General', ...
    #      sound=content://settings/system/notification_sound/Chime
    
    for line in content.splitlines():
        line = line.strip()
        
        # Detect start of a channel block
        # Format often looks like: Channel{id='...', name='...', importance=...}
        if line.startswith("Channel{"):
            # Extract ID using regex
            match = re.search(r"id='([^']*)'", line)
            if match:
                current_channel = match.group(1)
                channels[current_channel] = {"raw": line}
                
        # Extract sound field
        # Format often: sound=content://... or sound=null
        elif current_channel and "sound=" in line:
            parts = line.split("sound=")
            if len(parts) > 1:
                sound_val = parts[1].split(' ')[0].strip() # Take up to next space or comma
                # Remove trailing commas/brackets if parsing is messy
                sound_val = sound_val.rstrip(',}')
                channels[current_channel]['sound'] = sound_val

    return channels

def verify_notification_sound(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Setup temp files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_initial = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_final = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # 1. Retrieve Artifacts
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        copy_from_env(result_data["initial_state_path"], temp_initial.name)
        with open(temp_initial.name, 'r') as f:
            initial_content = f.read()
            
        copy_from_env(result_data["final_state_path"], temp_final.name)
        with open(temp_final.name, 'r') as f:
            final_content = f.read()

        # 2. Parse Notification States
        initial_channels = parse_dumpsys_notification(initial_content)
        final_channels = parse_dumpsys_notification(final_content)
        
        # Identify the target channel (usually 'miscellaneous', 'default', or 'general')
        # We look for the one that exists in both and changed, or the main one
        target_channel_id = None
        
        # Heuristic: Find a channel where sound changed
        for cid, data in final_channels.items():
            if cid in initial_channels:
                init_sound = initial_channels[cid].get('sound', 'default')
                final_sound = data.get('sound', 'default')
                if init_sound != final_sound:
                    target_channel_id = cid
                    break
        
        # If no change detected, fallback to finding the main channel to check logic
        if not target_channel_id:
            possible_ids = ['miscellaneous', 'general', 'default', 'channel_1']
            for pid in possible_ids:
                if pid in final_channels:
                    target_channel_id = pid
                    break
            # If still nothing, take the first one
            if not target_channel_id and final_channels:
                target_channel_id = list(final_channels.keys())[0]

        if not target_channel_id:
             return {"passed": False, "score": 0, "feedback": "Could not identify any notification channels for the app."}

        initial_sound = initial_channels.get(target_channel_id, {}).get('sound', 'unknown')
        final_sound = final_channels.get(target_channel_id, {}).get('sound', 'unknown')
        
        logger.info(f"Channel: {target_channel_id}")
        logger.info(f"Initial Sound: {initial_sound}")
        logger.info(f"Final Sound: {final_sound}")

        # 3. Verify Change Logic
        score = 0
        feedback = []
        
        # Criterion A: Sound Changed (40 pts)
        if initial_sound != final_sound:
            score += 40
            feedback.append(f"Sound changed successfully (from {initial_sound.split('/')[-1]} to {final_sound.split('/')[-1]})")
        else:
            feedback.append("Sound setting was NOT changed")

        # Criterion B: New Sound is NOT default (30 pts)
        # Default often looks like 'content://settings/system/notification_sound' (without specific name) or 'null' or 'default'
        # Specific sounds usually append the name, e.g., '.../Chime'
        is_default = 'default' in final_sound.lower() or final_sound == 'null'
        if not is_default:
            score += 30
            feedback.append("New sound is not system default")
        else:
            feedback.append("Sound is still set to default")

        # Criterion C: Starts with 'C' (30 pts)
        # Extract filename from URI: content://.../Chime -> Chime
        sound_name = final_sound.split('/')[-1]
        if sound_name and sound_name[0].upper() == 'C':
            score += 30
            feedback.append(f"Selected sound '{sound_name}' starts with 'C'")
        elif sound_name:
            # Partial credit if they changed it but picked wrong letter
            score += 10 
            feedback.append(f"Selected sound '{sound_name}' does not start with 'C'")

        # 4. VLM Trajectory Verification (Backup/Sanity Check)
        # If programmatic check is ambiguous, or to verify UI navigation
        if score < 100 and score > 0:
            frames = sample_trajectory_frames(traj, n=5)
            vlm_prompt = "Does this screenshot show the Android Notification Settings or Sound Selection screen? Is a sound like 'Chime' or 'Carbon' selected?"
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get("success") and "yes" in str(vlm_res.get("parsed", "")).lower():
                score += 10
                feedback.append("VLM confirms settings navigation.")

        passed = score >= 70
        
        return {
            "passed": passed,
            "score": min(100, score),
            "feedback": "; ".join(feedback),
            "details": {
                "channel_id": target_channel_id,
                "initial_sound": initial_sound,
                "final_sound": final_sound
            }
        }

    except Exception as e:
        logger.exception("Verification failed with exception")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
        
    finally:
        # Cleanup
        for fpath in [temp_json.name, temp_initial.name, temp_final.name]:
            if os.path.exists(fpath):
                os.unlink(fpath)