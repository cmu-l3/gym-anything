#!/usr/bin/env python3
"""
Verifier for configure_patient_interface task.

Checks:
1. interface_config.js: DEFAULT_WELCOME_PAGE_TITLE == "Hospital Virtual Care"
2. interface_config.js: SETTINGS_SECTIONS == ['devices', 'sounds'] (and no others)
3. interface_config.js: MOBILE_APP_PROMO == false
4. Screenshot exists and VLM confirms Settings dialog is restricted.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_js_config(content):
    """
    Naive parsing of the JS config file using regex.
    We are looking for specific keys assigned in the interfaceConfig object.
    """
    config = {}
    
    # Extract DEFAULT_WELCOME_PAGE_TITLE
    # Matches: DEFAULT_WELCOME_PAGE_TITLE: 'Value',
    title_match = re.search(r"DEFAULT_WELCOME_PAGE_TITLE:\s*['\"]([^'\"]+)['\"]", content)
    if title_match:
        config['title'] = title_match.group(1)
        
    # Extract MOBILE_APP_PROMO
    # Matches: MOBILE_APP_PROMO: false,
    promo_match = re.search(r"MOBILE_APP_PROMO:\s*(true|false)", content, re.IGNORECASE)
    if promo_match:
        config['promo'] = promo_match.group(1).lower() == 'true'
        
    # Extract SETTINGS_SECTIONS
    # Matches: SETTINGS_SECTIONS: [ ... ],
    # This is multiline, so we need dotall or careful matching
    settings_match = re.search(r"SETTINGS_SECTIONS:\s*\[(.*?)\]", content, re.DOTALL)
    if settings_match:
        raw_list = settings_match.group(1)
        # cleanup quotes and whitespace
        items = [item.strip().strip("'").strip('"') for item in raw_list.split(',') if item.strip()]
        config['settings'] = items
        
    return config

def verify_configure_patient_interface(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 2. Analyze Config File
    config_valid = False
    if result_data.get("config_found"):
        # Copy the extracted config file
        temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.js')
        try:
            copy_from_env(result_data["config_path"], temp_config.name)
            with open(temp_config.name, 'r') as f:
                content = f.read()
            
            parsed = parse_js_config(content)
            
            # Check Title (20 pts)
            expected_title = "Hospital Virtual Care"
            if parsed.get('title') == expected_title:
                score += 20
                feedback.append(f"Title correctly set to '{expected_title}'")
            else:
                feedback.append(f"Title mismatch: found '{parsed.get('title')}'")

            # Check Promo (20 pts)
            if 'promo' in parsed and parsed['promo'] is False:
                score += 20
                feedback.append("Mobile promo disabled")
            else:
                feedback.append(f"Mobile promo not disabled (value: {parsed.get('promo')})")

            # Check Settings Sections (25 pts)
            # Expected: ONLY devices and sounds. Order doesn't strictly matter, but exact match of set.
            current_settings = set(parsed.get('settings', []))
            expected_settings = {'devices', 'sounds'}
            
            if current_settings == expected_settings:
                score += 25
                feedback.append("Settings tabs correctly restricted")
                config_valid = True
            else:
                feedback.append(f"Settings tabs mismatch. Found: {list(current_settings)}")

        except Exception as e:
            feedback.append(f"Error parsing config file: {str(e)}")
        finally:
            if os.path.exists(temp_config.name):
                os.unlink(temp_config.name)
    else:
        feedback.append("Could not retrieve interface_config.js from container")

    # 3. Check Browser Title (15 pts)
    # This proves the user actually reloaded the page
    browser_title = result_data.get("browser_title", "")
    if "Hospital Virtual Care" in browser_title:
        score += 15
        feedback.append("Browser window title confirmed")
    else:
        feedback.append(f"Browser title did not match (Found: '{browser_title}')")

    # 4. VLM Verification of Screenshot (20 pts)
    # We verify the agent's explicit proof screenshot if it exists, otherwise the final desktop
    screenshot_path = result_data.get("screenshot_path") if result_data.get("screenshot_exists") else result_data.get("final_desktop_screenshot")
    
    vlm_passed = False
    if screenshot_path:
        # We need to get the file locally to pass to VLM
        # The path in result_data is the container path. We need to copy it out.
        # However, the VLM utility usually expects an image object or bytes.
        # Note: The provided `query_vlm` handles local paths if run in the framework context, 
        # but here we need to extract the file content first.
        
        # Actually, `get_final_screenshot(traj)` gets the last frame from trajectory, 
        # but the task asks for a specific screenshot file created by the agent.
        # We will use the agent's screenshot if available, else trajectory.
        
        # For this verification script, let's use the provided `query_vlm` with the trajectory final screenshot 
        # as a fallback if the file copy fails, but try to use the agent's file.
        
        # Copy agent screenshot to temp
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(screenshot_path, temp_img.name)
            
            prompt = """
            You are verifying a Jitsi Meet task. 
            Look at this screenshot of the Settings dialog.
            
            1. Is the 'Settings' dialog or modal open?
            2. Do you see the tabs 'Devices' and 'Sounds'?
            3. Are there ANY OTHER tabs visible (like Profile, Calendar, More)?
            
            Expected: Only 'Devices' and 'Sounds' should be listed in the header.
            
            Return JSON:
            {
                "dialog_open": boolean,
                "devices_tab_visible": boolean,
                "sounds_tab_visible": boolean,
                "other_tabs_visible": boolean,
                "title_visible": boolean (do you see 'Hospital Virtual Care' anywhere?)
            }
            """
            
            vlm_response = query_vlm(prompt=prompt, image=temp_img.name)
            
            if vlm_response.get('success'):
                parsed = vlm_response['parsed']
                if parsed.get('dialog_open') and parsed.get('devices_tab_visible') and not parsed.get('other_tabs_visible'):
                    score += 20
                    vlm_passed = True
                    feedback.append("VLM confirmed restricted settings dialog")
                else:
                    feedback.append(f"VLM check failed: {json.dumps(parsed)}")
            
        except Exception as e:
            feedback.append(f"VLM verification error: {e}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)
    else:
        feedback.append("No screenshot available for verification")

    passed = (score >= 65) and config_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }