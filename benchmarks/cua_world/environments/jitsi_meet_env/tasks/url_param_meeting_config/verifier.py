#!/usr/bin/env python3
"""
Verifier for url_param_meeting_config task.

Verifies that the agent:
1. Constructed a Jitsi URL with correct hash parameters.
2. Saved the URL and a report to the specified files.
3. Successfully configured the meeting (verified via VLM on screenshots).

Metrics:
- Programmatic: File existence, timestamp validity, URL content analysis.
- Visual (VLM): Checks if meeting subject is visible and AV is muted in the screenshot.
"""

import json
import os
import tempfile
import logging
import urllib.parse
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_url_param_meeting_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_room = metadata.get('required_room', 'VirtualBootcamp2024').lower()
    
    score = 0
    feedback_parts = []
    
    # 1. Load basic task result JSON
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # 2. Verify URL File Content (30 points)
    url_file_exists = task_result.get('url_file_exists', False)
    if url_file_exists and task_result.get('url_file_size', 0) > 10:
        temp_url = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/home/ga/meeting_url.txt", temp_url.name)
            with open(temp_url.name, 'r') as f:
                url_content = f.read().strip()
                
            # Analyze URL
            # Expected format: .../RoomName#config.param1=val&config.param2=val
            score += 10
            feedback_parts.append("URL file exists.")

            if required_room in url_content.lower():
                score += 5
                feedback_parts.append("Correct room name in URL.")
            
            # Check for parameters
            params_found = 0
            if "config.startWithAudioMuted=true" in url_content:
                params_found += 1
            if "config.startWithVideoMuted=true" in url_content:
                params_found += 1
            if "config.subject" in url_content and "Bootcamp" in url_content:
                params_found += 1
            
            # Flexible check for subject encoding (spaces vs %20)
            if "Morning" in url_content and "Advanced" in url_content:
                 feedback_parts.append("Subject text present in URL.")

            score += (params_found * 5) # Up to 15 points
            if params_found == 3:
                feedback_parts.append("All configuration parameters found in URL.")
            else:
                feedback_parts.append(f"Found {params_found}/3 configuration parameters.")
                
        except Exception as e:
            feedback_parts.append(f"Error reading URL file: {str(e)}")
        finally:
            if os.path.exists(temp_url.name):
                os.unlink(temp_url.name)
    else:
        feedback_parts.append("URL file missing or empty.")

    # 3. Verify Report File (10 points)
    if task_result.get('report_file_exists', False) and task_result.get('report_file_size', 0) > 50:
        score += 10
        feedback_parts.append("Configuration report created.")
    else:
        feedback_parts.append("Configuration report missing.")

    # 4. Verify Agent Screenshot Exists (10 points)
    if task_result.get('screenshot_exists', False) and task_result.get('screenshot_is_fresh', False):
        score += 10
        feedback_parts.append("Screenshot saved.")
    else:
        feedback_parts.append("Screenshot missing or outdated.")

    # 5. VLM Verification (50 points)
    # We use the agent's screenshot if available, otherwise the system final screenshot
    
    # Retrieve the agent's screenshot for VLM analysis
    image_to_check = None
    if task_result.get('screenshot_exists', False):
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/home/ga/meeting_configured.png", temp_img.name)
            image_to_check = temp_img.name
        except:
            pass # Fallback to final screenshot if copy fails
            
    # Fallback to system screenshot if agent screenshot invalid
    if not image_to_check:
        image_to_check = get_final_screenshot(traj)

    if image_to_check and os.path.getsize(image_to_check) > 0:
        prompt = """
        Analyze this screenshot of a Jitsi Meet video conference.
        
        Check for the following SPECIFIC visual elements:
        1. Is the meeting subject/title visible at the top? It should contain "Morning Bootcamp" or "Advanced Level".
        2. Is the microphone icon visible and does it indicate MUTED state (usually red, slashed, or 'unmute' prompt)?
        3. Is the camera/video icon visible and does it indicate MUTED/OFF state?
        4. Is the interface generally visible (not a blank screen or error page)?
        
        Respond in JSON:
        {
            "subject_visible": boolean,
            "subject_text_correct": boolean,
            "audio_muted": boolean,
            "video_muted": boolean,
            "meeting_interface_visible": boolean,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_res = query_vlm(prompt=prompt, image=image_to_check)
        
        if vlm_res and vlm_res.get('success'):
            analysis = vlm_res.get('parsed', {})
            
            if analysis.get('meeting_interface_visible', False):
                score += 10
                feedback_parts.append("Meeting interface verified.")
                
                if analysis.get('subject_visible', False) and analysis.get('subject_text_correct', False):
                    score += 15
                    feedback_parts.append("Meeting subject correctly applied.")
                
                if analysis.get('audio_muted', False):
                    score += 12.5
                    feedback_parts.append("Audio verified muted.")
                    
                if analysis.get('video_muted', False):
                    score += 12.5
                    feedback_parts.append("Video verified muted.")
            else:
                feedback_parts.append("VLM could not confirm meeting interface visibility.")
        else:
            feedback_parts.append("VLM analysis failed.")
            # Partial credit if file exists but VLM fails? No, reliability first.
    else:
        feedback_parts.append("No valid screenshot available for verification.")

    # Cleanup temp image
    if image_to_check and os.path.exists(image_to_check) and "/tmp/" in image_to_check:
        try:
            os.unlink(image_to_check)
        except:
            pass

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }