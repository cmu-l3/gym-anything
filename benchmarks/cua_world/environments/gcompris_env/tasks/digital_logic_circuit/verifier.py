#!/usr/bin/env python3
"""
Verifier for GCompris Digital Logic Circuit task.

Verification Strategy:
1. File Evidence (10%): Checks if the agent saved the requested screenshot.
2. VLM Verification (90%): Analyzes the trajectory and final state to confirm:
   - The user navigated to the Digital Electronics activity.
   - The circuit contains the required components (2 switches, 1 AND gate, 1 bulb).
   - The components are wired correctly.
   - The final state shows the bulb illuminated (logic verification).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_digital_logic_circuit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results (File existence check)
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. VLM Verification
    frames = sample_trajectory_frames(traj, n=6)
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        frames.append(final_screenshot)

    vlm_prompt = """
    You are an expert verifier for an educational digital electronics task.
    The user was asked to build a specific circuit in GCompris:
    - 2 Switches (Inputs)
    - 1 AND Gate
    - 1 Light Bulb (Output)
    - Wired as: Switch 1 & Switch 2 -> AND Gate -> Light Bulb
    - Final State: Both switches ON, Light Bulb ON.

    Analyze the provided screenshots of the user's session.
    
    Determine the following:
    1. Did the user open the 'Digital Electronics' activity? (Look for a grid workspace with electronic symbols toolbar)
    2. Are the correct components present? (Two switches, one D-shaped AND gate, one bulb)
    3. Is the wiring correct? (Lines connecting switches to gate inputs, gate output to bulb)
    4. Is the circuit active/working? (Are the switches in the 'closed/on' position? Is the bulb colored/glowing/lit up?)

    Provide a JSON response:
    {
        "activity_opened": true/false,
        "components_correct": true/false,
        "wiring_correct": true/false,
        "bulb_lit": true/false,
        "confidence": 0-10,
        "reasoning": "Description of what you see"
    }
    """

    vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_data = {}
    if vlm_response and vlm_response.get("success"):
        vlm_data = vlm_response.get("parsed", {})
    else:
        logger.error(f"VLM query failed: {vlm_response.get('error')}")

    # 3. Scoring
    score = 0
    feedback = []

    # Criterion 1: Activity Navigation (20 pts)
    if vlm_data.get("activity_opened"):
        score += 20
        feedback.append("Correct activity opened.")
    else:
        feedback.append("Failed to identify Digital Electronics activity.")

    # Criterion 2: Component Placement (20 pts)
    if vlm_data.get("components_correct"):
        score += 20
        feedback.append("Correct components placed (2 switches, 1 AND gate, 1 bulb).")
    else:
        feedback.append("Incorrect components found.")

    # Criterion 3: Wiring (25 pts)
    if vlm_data.get("wiring_correct"):
        score += 25
        feedback.append("Circuit wired correctly.")
    else:
        feedback.append("Wiring appears incorrect or incomplete.")

    # Criterion 4: Simulation Success (25 pts)
    if vlm_data.get("bulb_lit"):
        score += 25
        feedback.append("Circuit successfully activated (Bulb lit).")
    else:
        feedback.append("Circuit not active or bulb not lit.")

    # Criterion 5: Evidence Saved (10 pts)
    if task_result.get("evidence_exists") and task_result.get("evidence_valid_timestamp"):
        score += 10
        feedback.append("Screenshot evidence saved correctly.")
    elif task_result.get("evidence_exists"):
        score += 5
        feedback.append("Screenshot saved but timestamp suspicious.")
    else:
        feedback.append("No screenshot evidence saved by agent.")

    passed = score >= 65 and vlm_data.get("wiring_correct")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "vlm_analysis": vlm_data,
            "file_check": task_result
        }
    }