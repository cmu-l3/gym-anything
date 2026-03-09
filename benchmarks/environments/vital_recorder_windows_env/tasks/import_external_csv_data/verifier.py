#!/usr/bin/env python3
"""
Verifier for import_external_csv_data task.

Task: Import CSV data into Vital Recorder, visualize it, and save as .vital file.

Verification Strategy:
1. File Artifacts: Check if 'device_test_import.vital' exists and is a valid size.
2. Anti-Gaming: Check if file was created after task start.
3. Visualization: Use VLM to verify the screenshot shows the imported waveform.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_external_csv_data(traj, env_info, task_info):
    """
    Verify that the CSV data was imported, visualized, and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # ================================================================
    # 1. Retrieve Result JSON from Container
    # ================================================================
    # Note: path in container is Windows format, but copy_from_env usually handles path mapping 
    # or expects the internal path. The export script saved to C:\Users\Docker\AppData\Local\Temp\task_result.json
    # We try to copy from that location.
    
    windows_result_path = r"C:\Users\Docker\AppData\Local\Temp\task_result.json"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env(windows_result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result from Windows environment: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ================================================================
    # 2. Check File Artifacts (60 points)
    # ================================================================
    vital_exists = result.get('vital_file_exists', False)
    vital_size = result.get('vital_file_size_bytes', 0)
    created_during_task = result.get('vital_created_during_task', False)
    
    # Vital File Existence
    if vital_exists:
        score += 20
        feedback_parts.append("Vital file created.")
    else:
        feedback_parts.append("Vital file NOT found.")

    # Vital File Validity (Size > 1KB implies successful binary save of imported data)
    if vital_size > 1024:
        score += 20
        feedback_parts.append(f"Vital file size valid ({vital_size} bytes).")
    elif vital_exists:
        feedback_parts.append(f"Vital file too small ({vital_size} bytes).")

    # Anti-gaming (Timestamp)
    if created_during_task:
        score += 20
        feedback_parts.append("File created during task session.")
    elif vital_exists:
        feedback_parts.append("File timestamp indicates pre-existence (anti-gaming check failed).")

    # ================================================================
    # 3. VLM Verification of Visualization (40 points)
    # ================================================================
    # We check if the agent took a screenshot of the waveform
    
    screenshot_exists = result.get('screenshot_exists', False)
    
    if not screenshot_exists:
        feedback_parts.append("Screenshot of visualization NOT found.")
    else:
        # Get the screenshot file content for VLM
        # The agent saved it to C:\Users\Docker\Desktop\import_verification.png
        # We need to pull this specific file to analyze it
        
        screenshot_path_windows = r"C:\Users\Docker\Desktop\import_verification.png"
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        
        try:
            copy_from_env(screenshot_path_windows, temp_img.name)
            
            vlm_prompt = """
            You are verifying a task where a user imports a CSV file into Vital Recorder.
            Look at the screenshot.
            1. Is the Vital Recorder interface visible?
            2. Is there a waveform track visible (usually a line graph moving horizontally)?
            3. Does the waveform look like valid signal data (not a flat line)?
            
            Return JSON:
            {
                "vital_recorder_visible": true/false,
                "waveform_visible": true/false,
                "valid_signal": true/false,
                "reasoning": "..."
            }
            """
            
            # We use the specific screenshot the agent was asked to take
            vlm_result = query_vlm(prompt=vlm_prompt, image=temp_img.name)
            
            if vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if parsed.get('vital_recorder_visible', False):
                    score += 10
                if parsed.get('waveform_visible', False):
                    score += 15
                if parsed.get('valid_signal', False):
                    score += 15
                    feedback_parts.append("VLM confirms valid waveform visualization.")
                else:
                    feedback_parts.append(f"VLM Analysis: {parsed.get('reasoning', 'Signal not clear')}")
            else:
                feedback_parts.append("VLM verification failed to process.")
                
        except Exception as e:
            feedback_parts.append(f"Failed to analyze screenshot: {e}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)

    # ================================================================
    # 4. Final Scoring
    # ================================================================
    passed = score >= 80  # Requires valid file + some visualization evidence
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }