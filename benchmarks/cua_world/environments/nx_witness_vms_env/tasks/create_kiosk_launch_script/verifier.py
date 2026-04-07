#!/usr/bin/env python3
import json
import os
import base64
import re
import tempfile

def verify_create_kiosk_launch_script(traj, env_info, task_info):
    """
    Verify the kiosk launch script creation task.
    
    Criteria:
    1. File /home/ga/Desktop/launch_kiosk.sh exists (10 pts)
    2. File is executable (10 pts)
    3. Content calls a valid Nx Witness client executable (20 pts)
    4. Content includes correct auth flag (20 pts)
    5. Content includes correct layout flag (20 pts)
    6. Content includes fullscreen flag (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    score = 0
    feedback = []
    
    # 1. File Existence
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Script file /home/ga/Desktop/launch_kiosk.sh not found."
        }
    score += 10
    feedback.append("File created")

    # 2. Executable Permission
    if result.get("is_executable", False):
        score += 10
        feedback.append("File is executable")
    else:
        feedback.append("File is NOT executable (missing chmod +x)")

    # Decode content
    try:
        content_b64 = result.get("file_content_b64", "")
        script_content = base64.b64decode(content_b64).decode('utf-8')
    except Exception as e:
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Failed to read script content: {e}"
        }

    # Normalize content for checking (remove newlines inside command if possible, but regex handles it)
    # 3. Check for valid executable
    # Matches: networkoptix-client, nxwitness-client, or full paths to them
    exe_pattern = r"(networkoptix-client|nxwitness-client|miniclient|/opt/.*/bin/client)"
    if re.search(exe_pattern, script_content):
        score += 20
        feedback.append("Valid client executable called")
    else:
        feedback.append("No valid Nx Witness client executable found in script")

    # 4. Check for Auth
    # Expected: --auth=kiosk:Kiosk123! or --auth "kiosk:Kiosk123!"
    # Also valid: http://kiosk:Kiosk123!@localhost... (URL scheme)
    if "--auth" in script_content and "kiosk" in script_content and "Kiosk123!" in script_content:
        score += 20
        feedback.append("Auth flag configured correctly")
    elif "kiosk:Kiosk123!@" in script_content:
        score += 20
        feedback.append("Auth configured via URL scheme")
    else:
        feedback.append("Missing or incorrect authentication flags")

    # 5. Check for Layout
    # Expected: --layout-name "Lobby Monitor" or --layout-name="Lobby Monitor"
    if "--layout-name" in script_content and "Lobby Monitor" in script_content:
        score += 20
        feedback.append("Layout flag configured correctly")
    else:
        feedback.append("Missing or incorrect layout name flag")

    # 6. Check for Fullscreen
    # Expected: --full-screen or --fullscreen or -fs
    if re.search(r"(--full-screen|--fullscreen|-fs)", script_content):
        score += 20
        feedback.append("Fullscreen flag configured")
    else:
        feedback.append("Missing fullscreen flag")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback)
    }