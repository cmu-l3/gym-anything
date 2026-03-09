#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_navigate_timeline_window(traj, env_info, task_info):
    """
    Verifies that the agent zoomed to the correct 5-min window around the 20-min mark
    and saved the screenshot.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Programmatic Results
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Score File Existence & Timestamp (25 points)
    if result_data.get('output_exists'):
        if result_data.get('output_size_bytes', 0) > 1000: # Ensure not empty
            score += 15
            feedback_parts.append("Screenshot file exists.")
            
            if result_data.get('file_created_during_task'):
                score += 10
                feedback_parts.append("File created during task.")
            else:
                feedback_parts.append("File timestamp incorrect (pre-existing?).")
        else:
            feedback_parts.append("Screenshot file exists but is empty/too small.")
    else:
        feedback_parts.append("Screenshot file not found.")

    # 3. Retrieve Agent's Screenshot for VLM Analysis
    # We prioritize checking the file the agent SAVED.
    # If that doesn't exist, we fall back to the final screen state for partial credit 
    # (though the task explicitly asks to save a file).
    
    agent_image_path = None
    if result_data.get('output_exists'):
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            # Note: copy_from_env handles container paths. Windows paths in container might need
            # to be passed carefully. Usually the framework handles standard paths.
            # "C:\Users\Docker\Desktop\case_review_capture.png"
            copy_from_env("C:\\Users\\Docker\\Desktop\\case_review_capture.png", temp_img.name)
            agent_image_path = temp_img.name
        except Exception as e:
            logger.error(f"Failed to copy agent screenshot: {e}")

    # 4. VLM Verification
    if agent_image_path:
        prompt = """
        You are verifying a task in Vital Recorder software.
        The user was asked to:
        1. Zoom the timeline to show approximately a 5-minute window.
        2. Navigate to the 20-minute mark (00:20:00).
        
        Look at the provided screenshot.
        
        Q1: Is the Vital Recorder application visible with waveform tracks?
        Q2: Look at the time axis (usually at the top or bottom of tracks). Does the visible time range span roughly 3 to 7 minutes? (e.g. from 18:00 to 23:00 is 5 mins). If it shows 1 hour or 30 minutes, answer NO.
        Q3: Is the time centered roughly around 20 minutes (00:20:00)? (Acceptable range: 17:00 to 23:00 on the axis labels).
        
        Return JSON:
        {
            "app_visible": true/false,
            "zoom_level_correct": true/false,
            "position_correct": true/false,
            "explanation": "..."
        }
        """
        
        vlm_result = query_vlm(prompt=prompt, image=agent_image_path)
        
        if vlm_result['success']:
            parsed = vlm_result['parsed']
            if parsed.get('app_visible'):
                score += 10
                if parsed.get('zoom_level_correct'):
                    score += 25
                    feedback_parts.append("Zoom level appears correct (~5 min window).")
                else:
                    feedback_parts.append("Zoom level incorrect.")
                
                if parsed.get('position_correct'):
                    score += 25
                    feedback_parts.append("Timeline position correct (~20 min mark).")
                else:
                    feedback_parts.append("Timeline position incorrect.")
            else:
                feedback_parts.append("Vital Recorder app not clearly visible in screenshot.")
        
        # Cleanup
        if os.path.exists(agent_image_path):
            os.unlink(agent_image_path)
    else:
        feedback_parts.append("Skipping visual verification of saved file (file missing).")

    # 5. Trajectory Verification (Did they actually interact?)
    # Just a small bonus for showing work
    frames = sample_trajectory_frames(traj, n=3)
    if frames:
        traj_prompt = "Does the sequence of images show the user interacting with the Vital Recorder timeline (zooming or scrolling)? JSON: {'interacting': true/false}"
        traj_res = query_vlm(prompt=traj_prompt, images=frames)
        if traj_res['success'] and traj_res['parsed'].get('interacting'):
            score += 5
            feedback_parts.append("Trajectory shows interaction.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }