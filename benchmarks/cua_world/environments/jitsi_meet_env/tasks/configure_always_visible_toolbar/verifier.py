#!/usr/bin/env python3
import json
import os
import base64
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_always_visible_toolbar(traj, env_info, task_info):
    """
    Verifies that the Jitsi Meet toolbar is configured to be always visible.
    
    Criteria:
    1. Configuration file modified with correct setting (Primary).
    2. Web container restarted to apply changes (Anti-gaming).
    3. Evidence screenshot exists and shows toolbar (Secondary).
    4. VLM verification of the evidence.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback = []
    
    # 1. Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify Configuration File Content (30 points)
    config_exists = result.get("config_exists", False)
    config_modified = result.get("config_modified_during_task", False)
    config_content_b64 = result.get("config_content_base64", "")
    
    config_correct = False
    
    if config_exists:
        try:
            config_content = base64.b64decode(config_content_b64).decode('utf-8')
            # Check for the specific setting
            # Variations: TOOLBAR_ALWAYS_VISIBLE: true, TOOLBAR_ALWAYS_VISIBLE=true
            if "TOOLBAR_ALWAYS_VISIBLE" in config_content and "true" in config_content:
                # Basic string check passes, now check context ideally, but loose check is okay for config files
                # if the user wrote `TOOLBAR_ALWAYS_VISIBLE = true` or `TOOLBAR_ALWAYS_VISIBLE: true`
                score += 30
                config_correct = True
                feedback.append("Configuration file contains correct setting.")
            else:
                feedback.append("Configuration file exists but 'TOOLBAR_ALWAYS_VISIBLE' not set to 'true'.")
                
            if config_modified:
                score += 10
                feedback.append("Configuration file was modified during task.")
            else:
                feedback.append("Configuration file was NOT modified during task.")
        except Exception as e:
            feedback.append(f"Error parsing config content: {e}")
    else:
        feedback.append("Configuration file custom-interface_config.js not found.")

    # 3. Verify Container Restart (20 points)
    container_restarted = result.get("container_restarted_during_task", False)
    if container_restarted:
        score += 20
        feedback.append("Jitsi Web container was restarted to apply changes.")
    else:
        feedback.append("Jitsi Web container was NOT restarted (changes likely not applied).")

    # 4. Verify Evidence Screenshot (20 points)
    evidence_exists = result.get("evidence_screenshot_exists", False)
    
    vlm_passed = False
    if evidence_exists:
        score += 10 # Points just for saving the file
        feedback.append("Evidence screenshot found.")
        
        # Perform VLM Check
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            # The export script copied evidence to /tmp/evidence_screenshot.png
            copy_from_env("/tmp/evidence_screenshot.png", temp_img.name)
            
            prompt = """
            You are verifying a Jitsi Meet interface configuration task.
            The user was supposed to configure the toolbar (the row of buttons for mute, video, hangup, etc.) to be ALWAYS VISIBLE.
            
            Look at this screenshot.
            1. Is there a Jitsi Meet meeting in progress?
            2. Is the control toolbar (with microphone, camera, red hangup button) visible?
            3. Does the toolbar look standard (bottom center usually)?
            
            Return JSON:
            {
                "meeting_active": true/false,
                "toolbar_visible": true/false,
                "confidence": "low/medium/high"
            }
            """
            
            vlm_result = query_vlm(prompt=prompt, image=temp_img.name)
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("meeting_active") and parsed.get("toolbar_visible"):
                    score += 30
                    vlm_passed = True
                    feedback.append("VLM confirmed toolbar is visible in evidence screenshot.")
                else:
                    feedback.append(f"VLM did not detect visible toolbar: {parsed}")
            else:
                # If VLM fails, we fallback to just checking file existence logic or manual review
                feedback.append("VLM verification failed to run.")
                
        except Exception as e:
            feedback.append(f"Failed to process evidence screenshot: {e}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)
    else:
        feedback.append("No evidence screenshot saved to /home/ga/Documents/persistent_toolbar.png")

    # Total Score Calculation
    # Max possible: 30 (config content) + 10 (config modified) + 20 (restart) + 10 (file exists) + 30 (VLM) = 100
    
    passed = (score >= 70) and config_correct and container_restarted

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }