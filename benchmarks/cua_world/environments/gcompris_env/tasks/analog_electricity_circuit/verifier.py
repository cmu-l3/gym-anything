#!/usr/bin/env python3
"""
Verifier for GCompris Analog Electricity Circuit task.

Criteria:
1. Navigation: Agent found the electricity activity (VLM).
2. Construction: Agent placed battery, bulb, and wires (VLM).
3. Success: Bulb is lit/glowing (VLM).
4. Evidence: Screenshot file exists and was created during task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analog_electricity_circuit(traj, env_info, task_info):
    """
    Verify the electrical circuit task using VLM on trajectory and file checks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Load exported result JSON
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 2. File Verification (Anti-Gaming)
    # ================================================================
    output_exists = result.get("output_exists", False)
    created_during_task = result.get("file_created_during_task", False)
    output_size = result.get("output_size_bytes", 0)
    
    if output_exists:
        if created_during_task:
            if output_size > 5000:  # >5KB
                score += 10
                feedback_parts.append("Screenshot saved correctly.")
            else:
                score += 5
                feedback_parts.append("Screenshot saved but file is very small.")
        else:
            feedback_parts.append("Screenshot exists but is old (stale data).")
    else:
        feedback_parts.append("No screenshot saved to ~/circuit_complete.png.")

    if result.get("app_was_running", False):
        score += 10
        feedback_parts.append("GCompris was running.")

    # ================================================================
    # 3. VLM Trajectory Verification
    # ================================================================
    # We check frames to see if they navigated and built the circuit
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    # If agent saved a screenshot, try to use it for verification too
    # (In a real scenario we'd copy it out, but here we rely on the system 
    # final screenshot + trajectory which covers the screen anyway)
    
    vlm_prompt = """
    You are verifying a task where an agent must build an electrical circuit in GCompris.
    
    Review the sequence of images (trajectory) and the final state.
    
    Check for:
    1. ACTIVITY_FOUND: Did the screen change from the main menu to an activity with electrical components (batteries, bulbs)?
    2. COMPONENTS_PLACED: Can you see a battery and a light bulb placed on the workspace?
    3. WIRES_CONNECTED: Are there wires connecting the components?
    4. BULB_LIT: Is the light bulb GLOWING or LIT UP (usually shows rays or bright yellow color)?
    
    Return JSON:
    {
        "activity_found": boolean,
        "components_placed": boolean,
        "wires_connected": boolean,
        "bulb_lit": boolean,
        "explanation": "string"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screenshot], prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("activity_found"):
            score += 20
            feedback_parts.append("Navigated to electricity activity.")
            
        if parsed.get("components_placed"):
            score += 20
            feedback_parts.append("Components placed.")
            
        if parsed.get("wires_connected"):
            score += 10
            feedback_parts.append("Wires connected.")
            
        if parsed.get("bulb_lit"):
            score += 30
            feedback_parts.append("SUCCESS: Bulb is lit!")
        else:
            feedback_parts.append("Bulb does not appear to be lit.")
            
    else:
        feedback_parts.append("VLM verification failed.")

    # ================================================================
    # 4. Final Scoring
    # ================================================================
    passed = score >= 60 and parsed.get("bulb_lit", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }