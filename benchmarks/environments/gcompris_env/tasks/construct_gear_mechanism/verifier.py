#!/usr/bin/env python3
"""
Verifier for construct_gear_mechanism task.

Verification Strategy:
1. File Check (20 pts): Did the agent create 'gears_success.png' during the task?
2. Navigation Check (20 pts): VLM verifies the agent reached the Gears activity.
3. Solution Check (60 pts): VLM verifies the gears are connected and the puzzle is solved based on trajectory and final state.

Pass Threshold: 70 points.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_construct_gear_mechanism(traj, env_info, task_info):
    """
    Verify the gear mechanism construction task.
    """
    # 1. Setup and Load JSON Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # 2. File Verification (20 pts)
    evidence_exists = result.get('evidence_exists', False)
    evidence_valid = result.get('evidence_created_during_task', False)
    evidence_size = result.get('evidence_size_bytes', 0)

    if evidence_exists and evidence_valid and evidence_size > 5000:
        score += 20
        feedback_parts.append("Screenshot evidence created successfully (+20).")
    elif evidence_exists:
        score += 10
        feedback_parts.append("Screenshot exists but timestamp/size is suspicious (+10).")
    else:
        feedback_parts.append("No screenshot evidence found (0).")

    # 3. VLM Verification (80 pts total)
    # We use trajectory frames to check navigation and the final state for the solution.
    
    # Sample frames: Start, Middle, End
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    # If final screenshot is missing from trajectory, try to use the one exported by script
    if final_screenshot is None:
        # Note: In a real scenario we might pull /tmp/task_final.png from container, 
        # but here we rely on the framework's captured trajectory.
        pass

    all_images = frames + ([final_screenshot] if final_screenshot else [])
    
    if not all_images:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "No visual evidence available for verification."
        }

    # Prompt for VLM
    prompt = """
    You are evaluating an agent using the GCompris educational software.
    The task is to:
    1. Navigate to the "Gears" activity (icon shows interlocking gears).
    2. Construct a gear train connecting a motor gear to a target gear.
    
    Review the sequence of images provided.
    
    Check for the following:
    1. **Navigation**: Did the agent leave the main menu and open the Gears activity? (Look for a board with pegs and gears).
    2. **Construction**: Did the agent place loose gears onto the board?
    3. **Success**: Do you see a complete chain of gears connecting the driver (motor) to the target? Are there any visual indicators of success (e.g., "OK", "Level Completed", or rotation)?
    
    Output JSON:
    {
        "navigated_to_gears": true/false,
        "gears_placed": true/false,
        "chain_connected": true/false,
        "success_indicated": true/false,
        "confidence": "high/medium/low"
    }
    """

    vlm_result = query_vlm(images=all_images, prompt=prompt)
    
    if vlm_result.get("success"):
        analysis = vlm_result.get("parsed", {})
        
        # Navigation Score (20 pts)
        if analysis.get("navigated_to_gears"):
            score += 20
            feedback_parts.append("Verified navigation to Gears activity (+20).")
        else:
            feedback_parts.append("Failed to verify navigation to Gears activity.")

        # Construction Score (20 pts)
        if analysis.get("gears_placed"):
            score += 20
            feedback_parts.append("Verified gears were placed on the board (+20).")

        # Solution Score (40 pts)
        # We accept either specific success indication OR a visibly connected chain
        if analysis.get("success_indicated") or analysis.get("chain_connected"):
            score += 40
            feedback_parts.append("Verified functional gear chain constructed (+40).")
        else:
            feedback_parts.append("Could not verify completed gear chain.")
            
    else:
        feedback_parts.append(f"VLM verification failed: {vlm_result.get('error')}")

    # 4. Final Result
    # Pass threshold: 70 points
    # This requires: Evidence file (20) + Navigation (20) + Construction (20) + Partial Success (10)
    # OR: Navigation (20) + Construction (20) + Full Success (40) (Even without file)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }