#!/usr/bin/env python3
"""
Verifier for embed_meeting_iframe task.

Logic:
1. Verify the HTML file exists and was created during the task.
2. Analyze the HTML content to ensure correct API usage and configuration parameters.
3. Use VLM to verify the page was loaded in Firefox and shows the embedded meeting.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_embed_meeting_iframe(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Import VLM utilities
    try:
        from gym_anything.vlm import query_vlm, get_final_screenshot
    except ImportError:
        # Fallback for testing environments
        def query_vlm(prompt, image): return {"success": False}
        def get_final_screenshot(traj): return None

    score = 0
    feedback_parts = []
    
    # 1. Load basic result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check file existence and timestamp (Anti-gaming)
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "HTML file not found at ~/Documents/meeting_portal.html"}
    
    score += 10
    feedback_parts.append("File created")

    if result.get("file_created_during_task"):
        score += 10
        feedback_parts.append("File verified created during task")
    else:
        feedback_parts.append("Warning: File timestamp predates task start")

    # 3. Analyze HTML Content
    html_content = ""
    temp_html = tempfile.NamedTemporaryFile(delete=False, suffix='.html')
    try:
        # We copied the file to /tmp/submitted_portal.html in export_result.sh
        copy_from_env("/tmp/submitted_portal.html", temp_html.name)
        with open(temp_html.name, 'r', encoding='utf-8', errors='ignore') as f:
            html_content = f.read()
    except Exception as e:
        feedback_parts.append(f"Could not read HTML content: {e}")
    finally:
        if os.path.exists(temp_html.name):
            os.unlink(temp_html.name)

    if html_content:
        # Check API Script
        if "external_api.js" in html_content and "localhost:8080" in html_content:
            score += 10
            feedback_parts.append("API script referenced")
        else:
            feedback_parts.append("Missing or incorrect external_api.js reference")

        # Check Constructor
        if "JitsiMeetExternalAPI" in html_content:
            score += 10
            feedback_parts.append("API constructor used")
        else:
            feedback_parts.append("JitsiMeetExternalAPI constructor not found")

        # Check Room Name
        if "WeeklyOpsReview" in html_content:
            score += 10
            feedback_parts.append("Correct room name found")
        else:
            feedback_parts.append("Room name 'WeeklyOpsReview' not found in code")

        # Check Display Name
        if "Operations Manager" in html_content and "displayName" in html_content:
            score += 10
            feedback_parts.append("Display name configured")
        else:
            feedback_parts.append("Display name configuration missing")

        # Check Mute Settings
        if "startWithAudioMuted" in html_content and "true" in html_content.lower():
            score += 5
            feedback_parts.append("Audio mute configured")
        if "startWithVideoMuted" in html_content and "true" in html_content.lower():
            score += 5
            feedback_parts.append("Video mute configured")

        # Check Subject
        if "Weekly Operations Review" in html_content: # Partial match is okay
            score += 5
            feedback_parts.append("Subject configured")
    else:
        feedback_parts.append("HTML file was empty or unreadable")

    # 4. VLM Verification (Visual Check)
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    if final_screenshot:
        prompt = """
        You are verifying a Jitsi Meet task.
        The user was asked to create an HTML file that embeds a Jitsi meeting and open it in Firefox.
        
        Look at the screenshot and determine:
        1. Is Firefox open?
        2. Is the address bar showing a file:// URL (indicating a local file is open)?
        3. Is there a Jitsi Meet interface visible (meeting toolbar, video area, or pre-join screen)?
        4. Does it look like the meeting is loaded INSIDE the page (not just the default homepage)?
        
        Respond in JSON: {"firefox_open": bool, "is_local_file": bool, "meeting_visible": bool, "is_embedded": bool}
        """
        
        vlm_result = query_vlm(prompt=prompt, image=final_screenshot)
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("firefox_open"):
                vlm_score += 5
            if parsed.get("meeting_visible"):
                vlm_score += 15
                feedback_parts.append("Visual verification: Meeting visible")
            if parsed.get("is_local_file"):
                vlm_score += 5
                feedback_parts.append("Visual verification: Local file loaded")
        else:
            feedback_parts.append("VLM verification failed")
    
    score += vlm_score

    passed = score >= 75 and result.get("file_exists") and "WeeklyOpsReview" in html_content

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }