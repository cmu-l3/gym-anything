#!/usr/bin/env python3
"""
Verifier for enforce_global_lobby task.

Criteria:
1. Configuration: config.js must have `lobby: { autoEnable: true }` (40 pts)
2. Service Restart: The web container must have started AFTER task start (20 pts)
3. Meeting Active: Agent must be in a meeting (20 pts)
4. Visual Evidence: VLM sees Lobby/Shield icon (20 pts)
"""

import json
import os
import base64
import re
import tempfile
import logging
from datetime import datetime
import dateutil.parser

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enforce_global_lobby(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Import VLM utilities (assuming they are available in the python path or gym_anything)
    # Using the patterns from examples:
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    except ImportError:
        # Fallback for testing environment
        def sample_trajectory_frames(t, n): return []
        def get_final_screenshot(t): return t[-1]['screenshot'] if t and 'screenshot' in t[-1] else None
        def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

    score = 0
    feedback = []
    max_score = 100

    # 1. Fetch Task Result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # ------------------------------------------------------------------
    # Criterion 1: Configuration Check (40 pts)
    # ------------------------------------------------------------------
    config_valid = False
    if result_data.get('config_exists'):
        try:
            content = base64.b64decode(result_data['config_content_b64']).decode('utf-8')
            
            # Remove comments to avoid false positives (simple single line // removal)
            clean_lines = [line.split('//')[0] for line in content.split('\n')]
            clean_content = '\n'.join(clean_lines)

            # Look for lobby section and autoEnable: true
            # Pattern: lobby: { ... autoEnable: true ... }
            # We strip whitespace to make regex easier
            stripped_content = re.sub(r'\s+', '', clean_content)
            
            if 'lobby:{' in stripped_content and 'autoEnable:true' in stripped_content:
                # Need to ensure autoEnable:true is actually INSIDE lobby:{...}
                # A robust regex for nested JS objects is hard, but we can verify proximity
                lobby_match = re.search(r'lobby:\{([^}]+)\}', stripped_content)
                if lobby_match:
                    inner = lobby_match.group(1)
                    if 'autoEnable:true' in inner:
                        config_valid = True
                        score += 40
                        feedback.append("Configuration correct: Lobby autoEnable is true.")
                    else:
                        feedback.append("Found lobby section but autoEnable is not true.")
                else:
                    feedback.append("Could not parse lobby section correctly.")
            else:
                feedback.append("Lobby configuration missing or incorrect in config.js.")
        except Exception as e:
            feedback.append(f"Error parsing config file: {str(e)}")
    else:
        feedback.append("Config file not found.")

    # ------------------------------------------------------------------
    # Criterion 2: Service Restart Check (20 pts)
    # ------------------------------------------------------------------
    restart_valid = False
    if result_data.get('container_running'):
        task_start = result_data.get('task_start_ts', 0)
        container_start_iso = result_data.get('container_start_iso', '')
        
        if container_start_iso:
            try:
                # Handle ISO format with nanoseconds and timezone
                # Docker often gives: 2023-10-25T10:00:00.123456789Z
                container_start_dt = dateutil.parser.isoparse(container_start_iso)
                container_start_ts = container_start_dt.timestamp()
                
                # Check if container started AFTER task start (with small buffer)
                if container_start_ts > task_start:
                    restart_valid = True
                    score += 20
                    feedback.append("Service restarted successfully after config change.")
                else:
                    feedback.append(f"Service was not restarted (uptime predates task). Start: {container_start_ts}, Task: {task_start}")
            except Exception as e:
                feedback.append(f"Error parsing container timestamp: {e}")
        else:
            feedback.append("Could not get container start time.")
    else:
        feedback.append("Jitsi web container is not running.")

    # ------------------------------------------------------------------
    # Criterion 3 & 4: VLM Verification (Meeting Active + Visual Evidence) (40 pts)
    # ------------------------------------------------------------------
    # We use trajectory frames to ensure they actually did it, plus final screen
    final_img = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, 3)
    
    # We combine them, putting final image last
    all_images = frames + ([final_img] if final_img else [])

    if all_images:
        prompt = """
        You are verifying a Jitsi Meet task. The user was supposed to enable 'Lobby Mode' and join a meeting.
        
        Look at the provided screenshots. 
        1. Is the user inside a Jitsi meeting? (Look for video grid, toolbar at bottom, 'Invite people', etc.)
        2. Is there visual evidence that Lobby Mode is enabled? 
           - Look for an orange shield icon in the toolbar or header.
           - Look for text saying "Lobby mode is enabled".
           - Look for a participant list showing "Waiting for approval".
        
        Respond in JSON:
        {
            "in_meeting": true/false,
            "lobby_visible": true/false,
            "reasoning": "..."
        }
        """
        
        vlm_res = query_vlm(prompt=prompt, images=all_images)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            in_meeting = parsed.get('in_meeting', False)
            lobby_visible = parsed.get('lobby_visible', False)
            
            if in_meeting:
                score += 20
                feedback.append("Agent successfully entered a meeting.")
            else:
                feedback.append("VLM did not detect active meeting interface.")

            if lobby_visible:
                score += 20
                feedback.append("VLM detected visual evidence of Lobby Mode.")
            else:
                feedback.append("VLM did not detect Lobby Mode indicators (shield icon/text).")
        else:
            feedback.append("VLM verification failed to run.")
    else:
        feedback.append("No screenshots available for verification.")

    # ------------------------------------------------------------------
    # Final Decision
    # ------------------------------------------------------------------
    # Pass if Config is correct AND Restart happened AND (Meeting entered OR Lobby visible)
    # This prevents passing by just editing the file without testing.
    passed = config_valid and restart_valid and (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }