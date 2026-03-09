#!/usr/bin/env python3
"""
Verifier for customize_interface_focus_mode task.

Checks:
1. `custom-interface_config.js` exists and was modified during task.
2. content of config file sets `APP_NAME` to 'ExamPortal'.
3. content of config file sets `TOOLBAR_BUTTONS` to specific allowed list.
4. VLM verifies the UI actually reflects these changes (renamed app, simplified toolbar).
"""

import json
import base64
import re
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_interface_focus_mode(traj, env_info, task_info):
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
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

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_app_name = metadata.get('expected_app_name', 'ExamPortal')
    allowed_buttons = set(metadata.get('allowed_buttons', []))
    forbidden_buttons = set(metadata.get('forbidden_buttons', []))

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # CRITERION 1: Config File Exists & Created During Task (20 pts)
    # ------------------------------------------------------------------
    config_exists = result.get('config_exists', False)
    task_start = result.get('task_start', 0)
    config_mtime = result.get('config_mtime', 0)
    
    if config_exists:
        if config_mtime > task_start:
            score += 20
            feedback_parts.append("Config file created successfully.")
        else:
            score += 10
            feedback_parts.append("Config file exists but timestamp is old.")
    else:
        feedback_parts.append("Config file not found.")

    # ------------------------------------------------------------------
    # CRITERION 2: Config Content Analysis (40 pts)
    # ------------------------------------------------------------------
    config_content_b64 = result.get('config_content_base64', "")
    config_text = ""
    app_name_correct = False
    toolbar_correct = False

    if config_content_b64:
        try:
            config_text = base64.b64decode(config_content_b64).decode('utf-8', errors='ignore')
            
            # Check APP_NAME using regex
            # Looking for: APP_NAME: 'ExamPortal' OR APP_NAME = 'ExamPortal'
            app_name_match = re.search(r"APP_NAME\s*[:=]\s*['\"]([^'\"]+)['\"]", config_text)
            if app_name_match:
                found_name = app_name_match.group(1)
                if found_name == expected_app_name:
                    app_name_correct = True
                    score += 20
                    feedback_parts.append(f"APP_NAME correctly set to '{found_name}'.")
                else:
                    feedback_parts.append(f"APP_NAME set to '{found_name}', expected '{expected_app_name}'.")
            else:
                feedback_parts.append("APP_NAME setting not found in config.")

            # Check TOOLBAR_BUTTONS
            # This is harder to parse with regex if it spans multiple lines.
            # We'll look for the TOOLBAR_BUTTONS array definition.
            # Simplified approach: Extract list contents
            
            # Remove comments to avoid false positives
            clean_text = re.sub(r'//.*', '', config_text)
            clean_text = re.sub(r'/\*.*?\*/', '', clean_text, flags=re.DOTALL)
            
            # Find the array content
            toolbar_match = re.search(r"TOOLBAR_BUTTONS\s*[:=]\s*\[(.*?)\]", clean_text, flags=re.DOTALL)
            if toolbar_match:
                content = toolbar_match.group(1)
                # Find all quoted strings
                buttons_found = re.findall(r"['\"]([^'\"]+)['\"]", content)
                buttons_found_set = set(buttons_found)
                
                # Verify no forbidden buttons
                found_forbidden = buttons_found_set.intersection(forbidden_buttons)
                
                # Verify essential allowed buttons are present (at least majority)
                found_allowed = buttons_found_set.intersection(allowed_buttons)
                
                if not found_forbidden and len(found_allowed) >= 4:
                    toolbar_correct = True
                    score += 20
                    feedback_parts.append("TOOLBAR_BUTTONS correctly configured (only allowed buttons present).")
                elif found_forbidden:
                    feedback_parts.append(f"TOOLBAR_BUTTONS contains forbidden items: {found_forbidden}.")
                else:
                    feedback_parts.append("TOOLBAR_BUTTONS missing required items.")
            else:
                feedback_parts.append("TOOLBAR_BUTTONS setting not found.")

        except Exception as e:
            feedback_parts.append(f"Error parsing config content: {str(e)}")

    # ------------------------------------------------------------------
    # CRITERION 3: VLM Visual Verification (40 pts)
    # ------------------------------------------------------------------
    # Use trajectory frames to confirm they accessed the file system and UI
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    # Prompt for VLM
    prompt = f"""
    You are verifying a 'Focus Mode' configuration task in Jitsi Meet.
    
    Goal:
    1. The interface should be renamed to "{expected_app_name}".
    2. The toolbar should be simplified (NO Invite button, NO Security shield, NO Video Quality slider).
    
    Examine the provided images (screenshots from the agent's session).
    
    Question 1: Do you see the text "{expected_app_name}" anywhere in the interface (e.g., header, welcome screen, tab title)?
    Question 2: Looking at the meeting toolbar (bottom row of buttons), are the 'Invite' (person with +), 'Security' (shield), or 'Video Quality' buttons visible? They should be GONE.
    Question 3: Does the toolbar look simplified compared to a standard video call interface?
    
    Return JSON:
    {{
        "branding_visible": true/false,
        "forbidden_buttons_visible": true/false,
        "toolbar_simplified": true/false,
        "confidence": "high/medium/low"
    }}
    """
    
    vlm_score = 0
    try:
        if final_screen:
            # Add final screen to frames for analysis
            images_to_check = frames + [final_screen]
            result_vlm = query_vlm(prompt=prompt, images=images_to_check)
            
            if result_vlm.get('success'):
                parsed = result_vlm.get('parsed', {})
                branding = parsed.get('branding_visible', False)
                forbidden_visible = parsed.get('forbidden_buttons_visible', True)
                simplified = parsed.get('toolbar_simplified', False)
                
                if branding:
                    vlm_score += 15
                    feedback_parts.append("Visual confirmation: Branding correct.")
                
                if not forbidden_visible and simplified:
                    vlm_score += 25
                    feedback_parts.append("Visual confirmation: Toolbar simplified correctly.")
                elif not forbidden_visible:
                    vlm_score += 15
                    feedback_parts.append("Visual confirmation: Forbidden buttons removed.")
                else:
                    feedback_parts.append("Visual confirmation: Toolbar still shows forbidden buttons.")
            else:
                feedback_parts.append("VLM verification failed to process images.")
        else:
            feedback_parts.append("No screenshots available for VLM.")
            
    except Exception as e:
        feedback_parts.append(f"VLM error: {e}")

    score += vlm_score

    # ------------------------------------------------------------------
    # Final Calculation
    # ------------------------------------------------------------------
    passed = score >= 80 and app_name_correct and toolbar_correct
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }