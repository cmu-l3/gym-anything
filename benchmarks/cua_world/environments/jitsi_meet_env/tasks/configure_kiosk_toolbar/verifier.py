#!/usr/bin/env python3
"""
Verifier for configure_kiosk_toolbar task.
Checks if custom-config.js defines the correct restricted toolbar buttons and verifies visual outcome.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_kiosk_toolbar(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_buttons = set(metadata.get('required_buttons', []))
    prohibited_buttons = set(metadata.get('prohibited_buttons', []))

    # Load task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Config File Existence & Modification (20 pts)
    if result.get('config_exists') and result.get('config_modified'):
        score += 20
        feedback_parts.append("Config file modified")
    elif result.get('config_exists'):
        score += 10
        feedback_parts.append("Config file exists but timestamp suggests no change")
    else:
        feedback_parts.append("Config file not found")
        return {"passed": False, "score": 0, "feedback": "Config file missing"}

    # 2. Config Content Analysis (40 pts)
    # Copy the config file from container
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.js')
    config_valid = False
    try:
        copy_from_env("/tmp/submitted_config.js", temp_config.name)
        with open(temp_config.name, 'r') as f:
            content = f.read()
            
        # Look for toolbarButtons array definition
        # Regex to find: config.toolbarButtons = [ ... ] OR toolbarButtons: [ ... ]
        # Handling basic JS array syntax, potentially multiline
        # Simple robust approach: Remove whitespace/newlines, look for pattern
        clean_content = re.sub(r'\s+', '', content)
        
        # Pattern matches: toolbarButtons=['a','b'] or toolbarButtons=["a","b"]
        match = re.search(r'toolbarButtons\s*[:=]\s*\[([^\]]+)\]', content)
        if not match:
            # Try cleaning spaces
            match = re.search(r'toolbarButtons[:=]\[([^\]]+)\]', clean_content)
        
        if match:
            array_content = match.group(1)
            # Extract strings
            found_buttons = re.findall(r['"]([^'"]+)['"]', array_content)
            found_set = set(found_buttons)
            
            # Check for required buttons
            missing = required_buttons - found_set
            # Check for prohibited buttons
            extras = found_set.intersection(prohibited_buttons)
            
            if not missing and not extras:
                score += 40
                config_valid = True
                feedback_parts.append("Toolbar config is correct")
            else:
                if missing:
                    feedback_parts.append(f"Missing buttons: {missing}")
                if extras:
                    feedback_parts.append(f"Prohibited buttons found: {extras}")
                score += 10 # Partial credit for finding the setting
        else:
            feedback_parts.append("Could not parse 'toolbarButtons' array in config")

    except Exception as e:
        feedback_parts.append(f"Error reading config: {e}")
    finally:
        if os.path.exists(temp_config.name):
            os.unlink(temp_config.name)

    # 3. VLM Verification (40 pts)
    # Check if the final screenshot shows a simplified toolbar
    frames = sample_trajectory_frames(traj, n=3)
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        You are verifying a Jitsi Meet interface customization task.
        The goal is a 'Kiosk Mode' with a RESTRICTED toolbar containing ONLY:
        - Microphone
        - Camera
        - Hangup (Red button)
        - Tile View (Four squares)
        - Fullscreen (Arrows)

        Look at the screenshot.
        1. Is the Jitsi Meet toolbar visible at the bottom?
        2. Are the standard buttons like 'Chat', 'Share Screen', 'Invite', or 'Raise Hand' GONE?
        3. Do you see ONLY a small number of buttons (around 5)?

        Return JSON:
        {
            "toolbar_visible": true/false,
            "chat_button_visible": true/false,
            "share_screen_visible": true/false,
            "looks_simplified": true/false,
            "button_count_estimate": number
        }
        """
        
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('toolbar_visible'):
                if parsed.get('looks_simplified') and not parsed.get('chat_button_visible'):
                    score += 40
                    feedback_parts.append("Visual verification passed (Restricted toolbar detected)")
                elif parsed.get('chat_button_visible') or parsed.get('share_screen_visible'):
                    feedback_parts.append("Visual verification failed (Prohibited buttons visible)")
                else:
                    score += 20
                    feedback_parts.append("Toolbar visible but unsure if fully restricted")
            else:
                feedback_parts.append("Toolbar not clearly visible in final screenshot")
        else:
            feedback_parts.append("VLM check failed")

    passed = score >= 80 and config_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }