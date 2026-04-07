#!/usr/bin/env python3
"""
Verifier for configure_16ch_synthetic task.

Verification Logic:
1. File Check: Did the agent create the requested screenshot? (10 pts)
2. Timestamp Check: Was it created during the task? (10 pts)
3. App State: Is OpenBCI GUI running? (10 pts)
4. Visual Verification (VLM):
   - Is the GUI in an active session (not Control Panel)? (20 pts)
   - Are there 16 channels visible? (50 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_16ch_synthetic(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 2. Basic criteria (30 pts max)
    if result.get('app_was_running'):
        score += 10
        feedback_parts.append("OpenBCI GUI is running.")
    else:
        feedback_parts.append("OpenBCI GUI was NOT running at end of task.")

    screenshot_exists = result.get('agent_screenshot_exists')
    screenshot_valid = result.get('agent_screenshot_created_during_task')
    
    if screenshot_exists and screenshot_valid:
        score += 20
        feedback_parts.append("Agent screenshot created successfully.")
    elif screenshot_exists:
        score += 10
        feedback_parts.append("Agent screenshot exists but has invalid timestamp (pre-existing?).")
    else:
        feedback_parts.append("Agent did not save the screenshot as requested.")

    # 3. VLM Verification (70 pts max)
    # We prefer the agent's screenshot if it exists, otherwise we fallback to the final state screenshot
    # to give partial credit if they did the task but forgot to save the image.
    
    image_to_verify = None
    image_source = "none"
    
    if screenshot_exists and screenshot_valid:
        # Try to get the agent's screenshot
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(result['agent_screenshot_temp_path'], temp_img.name)
            image_to_verify = temp_img.name
            image_source = "agent"
        except Exception:
            logger.warning("Could not copy agent screenshot, falling back to final state.")
    
    if not image_to_verify:
        # Fallback to final state screenshot
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(result['final_state_screenshot_path'], temp_img.name)
            image_to_verify = temp_img.name
            image_source = "final_state"
        except Exception:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | No screenshots available for verification."}

    # Prepare VLM query
    prompt = (
        "You are verifying an OpenBCI GUI task. "
        "The user must start a session with 16 CHANNELS (Cyton+Daisy mode).\n\n"
        "Please analyze the image:\n"
        "1. Is the OpenBCI GUI visible and in an active session (showing data streams, not the startup menu)?\n"
        "2. Count the number of channel rows in the Time Series widget. Are there approximately 16 channels visible (numbered 1-16), or only 8?\n"
        "3. Do the channels show active waveforms (wavy lines) or are they flat/empty?\n\n"
        "Return JSON with keys: active_session (bool), channel_count_approx (int), 16_channels_confirmed (bool), waveforms_visible (bool)."
    )

    try:
        vlm_response = query_vlm(
            prompt=prompt,
            image=image_to_verify
        )
        
        # Clean up temp image
        if os.path.exists(image_to_verify):
            os.unlink(image_to_verify)
            
        if vlm_response.get("success"):
            analysis = vlm_response.get("parsed", {})
            logger.info(f"VLM Analysis: {analysis}")
            
            # Criterion: Active Session (20 pts)
            if analysis.get("active_session"):
                score += 20
                feedback_parts.append("Active session confirmed.")
                
                # Criterion: 16 Channels (40 pts)
                # We give full points if VLM explicitly confirms 16 channels
                if analysis.get("16_channels_confirmed") or analysis.get("channel_count_approx", 0) >= 12:
                    score += 40
                    feedback_parts.append("16-channel configuration verified.")
                elif analysis.get("channel_count_approx", 0) <= 8:
                    feedback_parts.append("Only ~8 channels detected. Did you select 16 channels in the setup?")
                else:
                    # Ambiguous count
                    score += 20
                    feedback_parts.append("Channel count ambiguous, but >8 detected.")
                
                # Criterion: Waveforms (10 pts)
                if analysis.get("waveforms_visible"):
                    score += 10
                    feedback_parts.append("Waveforms are active.")
            else:
                feedback_parts.append("GUI does not appear to be in an active session (still at menu?).")
        else:
            feedback_parts.append("VLM analysis failed.")
            
    except Exception as e:
        feedback_parts.append(f"Verification error: {str(e)}")
        if os.path.exists(image_to_verify):
            os.unlink(image_to_verify)

    # Final scoring logic
    # Pass if score >= 60 AND 16 channels were confirmed
    # We insist on the 16 channels being the key differentiator from the default state
    passed = (score >= 60) and ("16-channel" in " ".join(feedback_parts))

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }