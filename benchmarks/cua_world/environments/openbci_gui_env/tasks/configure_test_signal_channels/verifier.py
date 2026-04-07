#!/usr/bin/env python3
"""
Verifier for configure_test_signal_channels task.

Verifies that:
1. OpenBCI GUI is running.
2. A settings file was saved during the task.
3. The settings file contains the correct channel configurations:
   - Channels 1-4: Input Type = TESTSIG, Gain = 8x
   - Channels 5-8: Input Type = NORMAL, Gain = 24x
4. VLM verifies the visual trajectory (Hardware Settings panel interaction).
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_test_signal_channels(traj, env_info, task_info):
    """
    Verify the hardware settings configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_channels = metadata.get('target_channels', [0, 1, 2, 3])
    target_gain = metadata.get('target_gain', 8)
    default_channels = metadata.get('default_channels', [4, 5, 6, 7])
    default_gain = metadata.get('default_gain', 24)
    
    # Allow for variations in how the JSON stores "TESTSIG"
    target_input_types = metadata.get('target_input_type', ["TEST", "TESTSIG"])
    default_input_types = metadata.get('default_input_type', ["NORMAL"])

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check App Running (5 pts)
    if result.get('app_running', False):
        score += 5
        feedback_parts.append("OpenBCI GUI is running (+5)")
    else:
        feedback_parts.append("OpenBCI GUI is NOT running")

    # 3. Check Settings File (Primary Verification)
    settings_found = result.get('settings_found', False)
    settings_content = result.get('settings_content', {})
    
    file_score = 0
    if settings_found and settings_content:
        feedback_parts.append("Settings file found")
        
        # OpenBCI Settings structure typically has a "channels" key which is a list
        # OR "args" key with channel settings. Structure varies by version.
        # Common v5 structure: {"channels": [{"gain": 24, "inputType": "NORMAL", ...}, ...]}
        
        channels = settings_content.get('channels', [])
        
        if not channels:
            # Fallback for different JSON structure or empty file
            feedback_parts.append("Could not parse channel settings from file")
        elif len(channels) < 8:
            feedback_parts.append(f"Settings file has insufficient channels: {len(channels)}")
        else:
            # Verify Target Channels (1-4 -> indices 0-3)
            # Max 40 points (10 per channel)
            target_correct = 0
            for idx in target_channels:
                ch = channels[idx]
                gain = ch.get('gain')
                inp = ch.get('inputType', '').upper()
                
                # Check Gain
                gain_ok = (gain == target_gain) or (str(gain) == str(target_gain))
                
                # Check Input
                inp_ok = any(t in inp for t in target_input_types)
                
                if gain_ok and inp_ok:
                    target_correct += 1
                    file_score += 10
                else:
                    feedback_parts.append(f"Ch{idx+1} incorrect: Gain={gain} (exp {target_gain}), Input={inp}")

            if target_correct == len(target_channels):
                feedback_parts.append("Channels 1-4 configured correctly (+40)")

            # Verify Default Channels (5-8 -> indices 4-7)
            # Max 15 points
            defaults_correct = 0
            for idx in default_channels:
                ch = channels[idx]
                gain = ch.get('gain')
                inp = ch.get('inputType', '').upper()
                
                gain_ok = (gain == default_gain) or (str(gain) == str(default_gain))
                inp_ok = any(d in inp for d in default_input_types)
                
                if gain_ok and inp_ok:
                    defaults_correct += 1
            
            if defaults_correct == len(default_channels):
                file_score += 15
                feedback_parts.append("Channels 5-8 defaults preserved (+15)")
            else:
                feedback_parts.append(f"Channels 5-8 defaults modified ({defaults_correct}/{len(default_channels)} correct)")
                # Partial credit
                file_score += int((defaults_correct / len(default_channels)) * 15)
                
        # Bonus for creating the file during task
        file_score += 15
        feedback_parts.append("Settings saved during task (+15)")
        
    else:
        feedback_parts.append("No settings file saved")

    score += file_score

    # 4. VLM Verification (Trajectory Analysis) - 25 pts max
    # We check if the agent actually interacted with the Hardware Settings panel
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_ss = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of the OpenBCI GUI workflow.
        1. Do you see the 'Hardware Settings' panel? It typically looks like a list of channels (1-8) with columns for 'Power', 'Gain', 'Input Type', etc.
        2. Are channels 1, 2, 3, and 4 being modified?
        3. Can you see 'TEST' or 'TESTSIG' selected for the first four channels?
        4. Can you see 'x8' selected for the gain of the first four channels?
        
        Answer JSON: {"panel_opened": bool, "channels_modified": bool, "correct_values_visible": bool, "confidence": "low/medium/high"}
        """
        
        vlm_res = query_vlm(images=frames + [final_ss], prompt=prompt)
        parsed = vlm_res.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('panel_opened'):
            vlm_score += 10
            feedback_parts.append("VLM: Hardware panel opened")
        if parsed.get('correct_values_visible'):
            vlm_score += 15
            feedback_parts.append("VLM: Correct settings visible")
        elif parsed.get('channels_modified'):
            vlm_score += 10 # Partial credit if we saw mod but can't read values clearly
            feedback_parts.append("VLM: Channels modified")
            
        score += vlm_score
    else:
        feedback_parts.append("VLM verification unavailable (skipping)")
        # If VLM is missing but file was correct, scale score up to cover VLM portion? 
        # Or just accept file score. If file is perfect (70 pts + 5 running = 75), it passes.
        pass

    # Final Pass/Fail
    # Need 60 points + Key Criteria (Channels 1-4 correct in file OR VLM confirmed visual correctness)
    key_criteria_met = False
    if (file_score >= 40) or (score >= 60 and "Correct settings visible" in str(feedback_parts)):
        key_criteria_met = True

    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "; ".join(feedback_parts)
    }