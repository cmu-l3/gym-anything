#!/usr/bin/env python3
"""
Verifier for configure_input_type_noise_check task.

Verification Strategy:
1. File Verification: Check if agent created the screenshot at the correct path.
2. Timestamp Verification: Ensure it was created during the task.
3. VLM Verification: Analyze the *agent's* screenshot to confirm:
   - Hardware Settings panel is visible.
   - Channels 1-4 Input Type is "SHORTED".
   - Channels 5-8 Input Type is NOT "SHORTED" (should be default/NORMAL).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_input_type_noise_check(traj, env_info, task_info):
    """
    Verify configuration of Input Type to SHORTED for channels 1-4.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence & Validity (20 points)
    agent_screenshot_exists = result.get("agent_screenshot_exists", False)
    agent_screenshot_valid_time = result.get("agent_screenshot_valid_time", False)
    agent_screenshot_size = result.get("agent_screenshot_size", 0)

    if not agent_screenshot_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Agent failed to save the screenshot to the specified path."
        }

    if not agent_screenshot_valid_time:
        feedback_parts.append("Warning: Screenshot timestamp is outside task window.")
    else:
        score += 10
        feedback_parts.append("Screenshot created during task.")

    if agent_screenshot_size > 10000: # Arbitrary small threshold for non-empty image
        score += 10
    else:
        feedback_parts.append("Screenshot file is too small/empty.")

    # 3. Retrieve the agent's screenshot for VLM analysis
    # We prioritize the screenshot the agent took (as requested), as it should contain the modal/panel.
    # Fallback to system final screenshot if agent's screenshot is missing/corrupt, but description demanded specific file.
    local_screenshot_path = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    try:
        # We copied this to /tmp/agent_screenshot_evidence.png in export_result.sh
        copy_from_env("/tmp/agent_screenshot_evidence.png", local_screenshot_path)
    except Exception as e:
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Screenshot exists but could not be retrieved for verification: {e}"
        }

    # 4. VLM Verification (80 points)
    prompt = """
    You are verifying an OpenBCI GUI configuration task.
    Look at this screenshot of the Hardware Settings panel.
    
    Verification Criteria:
    1. Is the "Hardware Settings" panel visible? (It contains rows for Channels 1-8 and columns like 'PGA Gain', 'Input Type', 'Bias', etc.)
    2. Look at the 'Input Type' column (sometimes labeled 'Type').
    3. Verify that Channel 1, Channel 2, Channel 3, and Channel 4 are set to "SHORTED".
    4. Verify that Channel 5, Channel 6, Channel 7, and Channel 8 are NOT set to "SHORTED" (they should be "NORMAL" or similar).

    Respond in JSON format:
    {
        "hardware_panel_visible": true/false,
        "channels_1_to_4_shorted": true/false,
        "channels_5_to_8_not_shorted": true/false,
        "confidence": "high/medium/low",
        "reasoning": "Explain what you see for each channel row"
    }
    """

    try:
        vlm_response = query_vlm(
            prompt=prompt,
            images=[local_screenshot_path]
        )
        
        # Parse VLM response
        if isinstance(vlm_response, dict) and "parsed" in vlm_response:
            data = vlm_response["parsed"]
        else:
            # Fallback text parsing if JSON structure isn't perfect
            data = {"hardware_panel_visible": False, "channels_1_to_4_shorted": False}
            if "true" in str(vlm_response).lower():
                # Rough heuristic if parsing fails
                pass 

        # Scoring based on VLM
        if data.get("hardware_panel_visible", False):
            score += 20
            feedback_parts.append("Hardware Settings panel verified.")
            
            if data.get("channels_1_to_4_shorted", False):
                score += 40
                feedback_parts.append("Channels 1-4 confirmed SHORTED.")
            else:
                feedback_parts.append("Failed: Channels 1-4 are not all set to SHORTED.")

            if data.get("channels_5_to_8_not_shorted", True):
                score += 20
                feedback_parts.append("Channels 5-8 correctly left as default.")
            else:
                feedback_parts.append("Warning: Channels 5-8 were also modified (should be default).")
        else:
            feedback_parts.append("Hardware Settings panel not visible in screenshot.")

    except Exception as e:
        feedback_parts.append(f"VLM analysis failed: {e}")
    finally:
        if os.path.exists(local_screenshot_path):
            os.unlink(local_screenshot_path)

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }