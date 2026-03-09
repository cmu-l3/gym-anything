#!/usr/bin/env python3
"""
Verifier for lock_down_visitation_interface task.

Verifies:
1. Configuration file was modified to remove specific buttons.
2. Jitsi Web container was restarted to apply changes.
3. Visual confirmation (VLM) that buttons are missing from the UI.
"""

import json
import os
import re
import tempfile
import logging
import sys

# Add parent directory for shared utilities (vlm support)
# Assuming typical structure; if not, we define VLM helpers inline or rely on framework injection
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Mock or stub if running locally without framework
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj): return None
    def sample_trajectory_frames(traj, n): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lock_down_visitation_interface(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    forbidden_buttons = metadata.get('forbidden_buttons', ['chat', 'desktop', 'invite', 'embedmeeting'])

    # 1. Fetch Result JSON
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

    score = 0
    feedback_log = []

    # ------------------------------------------------------------------
    # CRITERION 1: Configuration Modification (35 pts)
    # ------------------------------------------------------------------
    config_modified = result_data.get('config_modified', False)
    config_path_in_container = result_data.get('config_copy_path')
    
    config_passed = False
    
    if config_modified and config_path_in_container:
        # Fetch the config file content
        temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.js')
        try:
            copy_from_env(config_path_in_container, temp_config.name)
            with open(temp_config.name, 'r') as f:
                config_content = f.read()
            
            # Extract TOOLBAR_BUTTONS array using regex
            # Look for: TOOLBAR_BUTTONS: [ ... ]
            # Using dotall to match across lines
            match = re.search(r'TOOLBAR_BUTTONS\s*:\s*\[(.*?)\]', config_content, re.DOTALL)
            
            if match:
                buttons_list_str = match.group(1)
                
                # Check for presence of forbidden buttons
                found_forbidden = []
                for btn in forbidden_buttons:
                    # Check for 'btn' or "btn"
                    if f"'{btn}'" in buttons_list_str or f'"{btn}"' in buttons_list_str:
                        found_forbidden.append(btn)
                
                if not found_forbidden:
                    score += 35
                    config_passed = True
                    feedback_log.append("Configuration modified correctly: Forbidden buttons removed.")
                else:
                    feedback_log.append(f"Configuration failed: Found forbidden buttons: {', '.join(found_forbidden)}")
            else:
                feedback_log.append("Configuration failed: Could not parse TOOLBAR_BUTTONS array in config file.")
                
        except Exception as e:
            feedback_log.append(f"Error reading configuration file: {str(e)}")
        finally:
            if os.path.exists(temp_config.name):
                os.unlink(temp_config.name)
    else:
        feedback_log.append("Configuration file was not modified or not found.")

    # ------------------------------------------------------------------
    # CRITERION 2: Service Restart (15 pts)
    # ------------------------------------------------------------------
    container_restarted = result_data.get('container_restarted', False)
    if container_restarted:
        score += 15
        feedback_log.append("Service restart verified.")
    else:
        feedback_log.append("Service verification failed: Jitsi web container was not restarted.")

    # ------------------------------------------------------------------
    # CRITERION 3: VLM Visual Verification (50 pts total)
    # ------------------------------------------------------------------
    # We use trajectory frames to ensure we capture the meeting state
    frames = sample_trajectory_frames(traj, n=3)
    final_shot = get_final_screenshot(traj)
    
    # Use final screenshot if available, otherwise last trajectory frame
    eval_images = [final_shot] if final_shot else []
    if not eval_images and frames:
        eval_images = [frames[-1]]
    
    vlm_passed = False
    
    if eval_images and eval_images[0]:
        prompt = """
        You are verifying a Jitsi Meet interface customization task.
        The goal was to REMOVE the 'Chat', 'Screen Share', and 'Invite' buttons from the toolbar.
        
        Analyze the screenshot of the meeting interface.
        1. Is the user inside a meeting? (Look for a main video area, toolbar at bottom).
        2. Are the following buttons VISIBLE on the toolbar?
           - Chat (Speech bubble icon)
           - Screen Share (Monitor/Screen icon)
           - Invite (Person with + icon)
           
        3. Are the standard buttons still there? (Microphone, Camera, Hangup red phone).
        
        Respond in JSON:
        {
            "in_meeting": true/false,
            "chat_visible": true/false,
            "screen_share_visible": true/false,
            "invite_visible": true/false,
            "mic_camera_visible": true/false
        }
        """
        
        vlm_res = query_vlm(prompt=prompt, images=eval_images)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            in_meeting = parsed.get('in_meeting', False)
            chat_vis = parsed.get('chat_visible', True)
            share_vis = parsed.get('screen_share_visible', True)
            invite_vis = parsed.get('invite_visible', True)
            mic_cam_vis = parsed.get('mic_camera_visible', False)
            
            # Scoring
            if in_meeting:
                score += 10
                feedback_log.append("Visual verification: Agent is in a meeting.")
                
                # Check for absence of restricted buttons
                buttons_gone = 0
                if not chat_vis:
                    score += 15
                    buttons_gone += 1
                else:
                    feedback_log.append("Visual failure: Chat button is still visible.")
                    
                if not share_vis:
                    score += 15
                    buttons_gone += 1
                else:
                    feedback_log.append("Visual failure: Screen Share button is still visible.")
                    
                if not invite_vis:
                    score += 10
                    buttons_gone += 1
                else:
                    feedback_log.append("Visual failure: Invite button is still visible.")
                
                if buttons_gone == 3:
                    vlm_passed = True
            else:
                feedback_log.append("Visual failure: Agent does not appear to be in a meeting.")
        else:
            feedback_log.append("VLM verification failed to execute.")
    else:
        feedback_log.append("No screenshots available for visual verification.")

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    # Pass threshold: 75 pts
    # Must have modified config AND restarted service to be considered valid engineering work
    # Visuals confirm it actually worked.
    
    passed = (score >= 75) and config_passed and container_restarted

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }