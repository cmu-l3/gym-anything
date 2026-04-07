#!/usr/bin/env python3
"""
Verifier for power_down_channels_hardware task.

Checks:
1. Settings file (PartialMontage.json) exists and was created during task.
2. JSON content confirms channels 1-3 are disabled (Power Down).
3. JSON content confirms channels 4-8 are enabled.
4. VLM verification of Hardware Settings panel (secondary).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_power_down_channels(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Task Result Metadata
    # ----------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence & Timestamp (Anti-gaming)
    # -------------------------------------------------
    if not result_meta.get('output_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Settings file 'PartialMontage.json' was not found."
        }
    
    score += 10
    feedback_parts.append("Settings file created")

    if result_meta.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created during task session")
    else:
        feedback_parts.append("WARNING: File timestamp predates task start")

    # 3. Analyze Settings JSON Content
    # --------------------------------
    settings_file_path = result_meta.get('settings_file_path')
    channels_correct = False
    
    if settings_file_path:
        temp_settings = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(settings_file_path, temp_settings.name)
            with open(temp_settings.name, 'r') as f:
                settings_data = json.load(f)
            
            # OpenBCI GUI Settings Structure Analysis
            # Typical v5 JSON structure:
            # { "channels": [ {"enabled": true/false, ...}, ... ], ... }
            
            channels = settings_data.get('channels', [])
            if not channels:
                # Fallback check for different versions/structures
                channels = settings_data.get('BoardCyton', {}).get('channels', [])

            if len(channels) >= 8:
                # Check Channels 1-3 (Indices 0, 1, 2) -> Should be DISABLED (false)
                # Check Channels 4-8 (Indices 3, 4, 5, 6, 7) -> Should be ENABLED (true)
                
                ch1_3_off = all(not ch.get('enabled', True) for ch in channels[0:3])
                ch4_8_on = all(ch.get('enabled', False) for ch in channels[3:8])
                
                if ch1_3_off:
                    score += 30
                    feedback_parts.append("Channels 1-3 correctly powered down")
                else:
                    feedback_parts.append("Failed: Channels 1-3 are not all powered down")
                    
                if ch4_8_on:
                    score += 20
                    feedback_parts.append("Channels 4-8 correctly kept active")
                else:
                    feedback_parts.append("Failed: Channels 4-8 should be active")
                
                if ch1_3_off and ch4_8_on:
                    channels_correct = True
            else:
                feedback_parts.append(f"Invalid settings file format: found {len(channels)} channels")
                
        except Exception as e:
            feedback_parts.append(f"Error parsing settings file: {str(e)}")
        finally:
            if os.path.exists(temp_settings.name):
                os.unlink(temp_settings.name)
    else:
        feedback_parts.append("Could not retrieve settings file content")

    # 4. VLM Verification (Trajectory & Final State)
    # ----------------------------------------------
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of the OpenBCI GUI.
        I am looking for evidence that the user:
        1. Opened the 'Hardware Settings' panel (a grid of buttons).
        2. Turned OFF channels 1, 2, and 3 (top row buttons for these columns should look different/greyed out).
        3. Saved the settings.
        
        Do you see the Hardware Settings panel open in any frame?
        Do the buttons for channels 1, 2, 3 look deactivated compared to 4-8?
        """
        
        try:
            # We use the frames to check if they opened the menu
            response = query_vlm(images=frames + [final_shot], prompt=prompt)
            
            # Simple keyword matching on VLM reasoning
            response_text = str(response).lower()
            if "hardware settings" in response_text and "open" in response_text:
                vlm_score += 15
                feedback_parts.append("VLM confirmed Hardware Settings panel usage")
            
            if "grey" in response_text or "off" in response_text or "deactivated" in response_text:
                vlm_score += 15
                feedback_parts.append("VLM confirmed visual channel deactivation")
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # If VLM fails, we rely on the strong file verification
            pass
            
    score += vlm_score

    # Final scoring logic
    # If file verification (programmatic) is perfect, we can pass even if VLM is unsure
    # Total possible points: 10 + 10 + 30 + 20 + 30 (VLM) = 100
    
    passed = (score >= 70) and channels_correct
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "; ".join(feedback_parts)
    }