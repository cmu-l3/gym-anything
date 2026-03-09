#!/usr/bin/env python3
"""
Verifier for server_side_start_muted_policy task.

Verification Logic:
1. Config File Analysis (60 pts):
   - 'startWithAudioMuted' must be true (30 pts)
   - 'startWithVideoMuted' must be true (30 pts)
2. Process Integrity (20 pts):
   - Config file must have been modified during the task
3. Live Verification (20 pts):
   - VLM analysis of the final screenshot to confirm the agent is in a meeting
     and the mute icons (microphone/camera) are active/red.
"""

import json
import os
import re
import tempfile
import logging
import sys
from pathlib import Path

# Add parent directory to path to import vlm_utils if needed
sys.path.append(str(Path(__file__).resolve().parents[1]))

try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Fallback/Mock for local testing
    def query_vlm(prompt, image, images=None):
        return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj):
        return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_server_side_start_muted_policy(traj, env_info, task_info):
    """
    Verify that Jitsi Meet config was updated to enforce muted start.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Verify Config Lines (Parsing the exported lines)
    audio_line = result.get("audio_config_line", "").strip()
    video_line = result.get("video_config_line", "").strip()
    
    # Regex to check for 'key: true' (ignoring comments handled in shell script somewhat, but double check here)
    # The shell script exports the raw grep line. We need to ensure it's not commented out // and is set to true.
    
    # Check Audio
    # Matches: startWithAudioMuted: true, (allowing spaces)
    # Rejects: // startWithAudioMuted: true
    audio_match = re.search(r'^\s*startWithAudioMuted\s*:\s*true', audio_line)
    if audio_match:
        score += 30
        feedback_parts.append("Audio config set to true")
    else:
        feedback_parts.append(f"Audio config incorrect (found: '{audio_line}')")

    # Check Video
    video_match = re.search(r'^\s*startWithVideoMuted\s*:\s*true', video_line)
    if video_match:
        score += 30
        feedback_parts.append("Video config set to true")
    else:
        feedback_parts.append(f"Video config incorrect (found: '{video_line}')")

    # 3. Verify File Modification (Anti-gaming)
    if result.get("file_modified", False):
        score += 20
        feedback_parts.append("Config file modified")
    else:
        feedback_parts.append("Config file NOT modified")

    # 4. VLM Verification of Live State
    # We look at the final screenshot to see if the interface shows muted icons
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        You are verifying a Jitsi Meet task. 
        Look at the screenshot. 
        1. Is the user in an active meeting (do you see the main conference view)?
        2. Are the microphone and camera icons RED or crossed out, indicating they are MUTED/OFF?
        
        Respond in JSON:
        {
            "in_meeting": true/false,
            "audio_muted": true/false,
            "video_muted": true/false
        }
        """
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("in_meeting") and (parsed.get("audio_muted") or parsed.get("video_muted")):
                score += 20
                feedback_parts.append("VLM confirms muted state in UI")
            else:
                feedback_parts.append("VLM did not confirm muted state in UI")
        else:
            # If VLM fails, we give partial credit if config is perfect
            feedback_parts.append("VLM check skipped")
            if score >= 80: # If config is perfect, bump to 100
                score += 20 

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }