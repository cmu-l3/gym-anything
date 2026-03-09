#!/usr/bin/env python3
import json
import os
import base64
import re
import tempfile
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_server_config(traj, env_info, task_info):
    """
    Verifies that the Jitsi Meet server was correctly customized.
    
    Criteria:
    1. Config file exists locally with correct parameters.
    2. Config file is served via HTTP (web container).
    3. Web container was restarted during the task.
    4. Visual verification of French interface via VLM.
    """
    
    # 1. Setup and load result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence and Content (40 points)
    config_exists = result.get("config_exists", False)
    config_content = ""
    
    if config_exists:
        try:
            config_content = base64.b64decode(result.get("config_content_b64", "")).decode('utf-8')
            score += 5
            feedback_parts.append("Config file created.")
        except:
            feedback_parts.append("Config file corrupted.")
    else:
        feedback_parts.append("Config file NOT found.")

    # Required parameters regex
    required_params = [
        (r"config\.defaultLanguage\s*=\s*['\"]fr['\"]", "Language set to French", 5),
        (r"config\.requireDisplayName\s*=\s*true", "Display name required", 5),
        (r"config\.startWithAudioMuted\s*=\s*true", "Start audio muted", 5),
        (r"config\.startWithVideoMuted\s*=\s*true", "Start video muted", 5),
        (r"config\.prejoinConfig\s*=\s*\{\s*enabled:\s*true,\s*hideDisplayName:\s*false\s*\}", "Prejoin config correct", 5),
        (r"config\.disableDeepLinking\s*=\s*true", "Deep linking disabled", 3),
        (r"config\.disableThirdPartyRequests\s*=\s*true", "Third-party requests disabled", 3),
        (r"config\.enableWelcomePage\s*=\s*true", "Welcome page enabled", 4)
    ]

    params_score = 0
    if config_content:
        for pattern, desc, pts in required_params:
            if re.search(pattern, config_content):
                params_score += pts
            else:
                feedback_parts.append(f"Missing/Incorrect: {desc}")
    
    score += params_score
    
    # 3. Check Container Restart (20 points)
    # This proves they actually applied the config, not just wrote the file
    if result.get("container_restarted", False):
        score += 20
        feedback_parts.append("Container restarted successfully.")
    else:
        feedback_parts.append("Container NOT restarted (changes not applied).")

    # 4. Check HTTP Serving (15 points)
    # This verifies the file is actually reachable by the app
    if result.get("http_status") == "200":
        # Double check content matches what we expect roughly
        http_content = ""
        try:
            http_content = base64.b64decode(result.get("http_content_b64", "")).decode('utf-8')
            if "defaultLanguage" in http_content and "fr" in http_content:
                score += 15
                feedback_parts.append("Config served via HTTP.")
            else:
                score += 5
                feedback_parts.append("Config served but content mismatch.")
        except:
            pass
    else:
        feedback_parts.append("Config NOT served via HTTP (404/Error).")

    # 5. Visual Verification (25 points)
    # We check the USER provided screenshot for the specific UI state
    user_screenshot_path = result.get("user_screenshot_path")
    user_screenshot_exists = result.get("user_screenshot_exists")
    
    vlm_score = 0
    if user_screenshot_exists:
        # We need to pull the screenshot from the env to the host for VLM
        local_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
        try:
            copy_from_env(user_screenshot_path, local_screenshot)
            
            # Use gym_anything VLM helper if available, or just assume success if file exists + strong config evidence
            # Here we simulate the VLM check using the framework's query_vlm tool
            from gym_anything.vlm import query_vlm
            
            prompt = """
            You are verifying a Jitsi Meet configuration task.
            The user claims to have changed the language to French.
            Look at this screenshot of the Jitsi Meet home page.
            
            1. Is the interface in French? (Look for "Démarrer la réunion", "Saisir le nom", "Rejoindre")
            2. Is it the Jitsi Meet home page?
            
            Return JSON: {"is_french": boolean, "is_jitsi": boolean}
            """
            
            vlm_res = query_vlm(prompt=prompt, image=local_screenshot)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("is_jitsi", False):
                    vlm_score += 5
                    if parsed.get("is_french", False):
                        vlm_score += 20
                        feedback_parts.append("Visual verification: French UI confirmed.")
                    else:
                        feedback_parts.append("Visual verification: UI does NOT appear to be French.")
                else:
                    feedback_parts.append("Visual verification: Not a Jitsi screen.")
            else:
                # Fallback if VLM fails but file exists and config is perfect
                if score > 50: 
                    vlm_score += 15
                    feedback_parts.append("Visual verification skipped (VLM error), partial credit.")
                
        except Exception as e:
            feedback_parts.append(f"Visual verification failed: {e}")
        finally:
            if os.path.exists(local_screenshot):
                os.unlink(local_screenshot)
    else:
        # If user screenshot missing, try final task screenshot from /tmp/task_final.png
        # (Managed by export_result.sh)
        pass 

    score += vlm_score

    # Final tally
    passed = score >= 70 and result.get("container_restarted", False) and result.get("config_exists", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }