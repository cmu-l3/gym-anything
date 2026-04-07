#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_map_selection(traj, env_info, task_info):
    """
    Verifies that the agent selected Charikar by panning the map and NOT by searching text.
    
    Strategy:
    1. VLM Analysis of Trajectory: Check for map panning gestures vs keyboard typing.
    2. VLM Analysis of Final State: Check if destination is set to Charikar/Route calculated.
    """
    
    # 1. Setup and Constraints
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 2. Retrieve artifacts
    temp_dir = tempfile.mkdtemp()
    final_screenshot_local = os.path.join(temp_dir, "final_state.png")
    
    try:
        copy_from_env("/sdcard/tasks/final_state.png", final_screenshot_local)
    except Exception as e:
        logger.error(f"Failed to copy final screenshot: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification evidence (screenshot)."}

    # 3. VLM Verification Logic
    # We need to sample frames to see the ACTION history
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    # If we couldn't get frames from traj, use the copied one as fallback for final
    if final_frame is None and os.path.exists(final_screenshot_local):
        from PIL import Image
        final_frame = Image.open(final_screenshot_local)
    
    all_evidence = frames + [final_frame] if final_frame else frames

    if not all_evidence:
        return {"passed": False, "score": 0, "feedback": "No video evidence available for verification."}

    # Construct VLM Prompt
    prompt = """
    You are verifying a GPS navigation task. 
    The user was instructed to:
    1. Center map on Kabul.
    2. MANUALLY pan North to find 'Charikar'.
    3. Tap 'Charikar' on the map to set it as destination.
    4. CONSTRAINT: Do NOT type 'Charikar' in the search bar.

    Analyze the image sequence.
    
    Q1: Did the user type "Charikar" into a search text field? (Look for keyboard and text "Charikar")
    Q2: Did the user manually drag/pan the map view? (Look for map moving between frames)
    Q3: Does the final screen show a computed route or navigation ready for "Charikar"?
    Q4: Did the user tap a specific location on the map (pin drop) rather than selecting from a search list?

    Output JSON:
    {
        "typed_forbidden_word": boolean,
        "panned_map": boolean,
        "final_destination_correct": boolean,
        "method_was_manual_selection": boolean,
        "reasoning": "string"
    }
    """

    # 4. Query VLM
    try:
        response = query_vlm(
            images=all_evidence,
            prompt=prompt
        )
        result_data = response.get('parsed', {})
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"VLM verification failed: {str(e)}"}

    # 5. Scoring
    score = 0
    feedback = []

    # Constraint Check (Critical Failure)
    if result_data.get("typed_forbidden_word", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: You typed 'Charikar' in the search bar. The task required manual map selection."
        }
    
    # Milestone 1: Panning (30 pts)
    if result_data.get("panned_map", False):
        score += 30
        feedback.append("Good: Manual map panning detected.")
    else:
        feedback.append("Missing: Did not see manual map navigation.")

    # Milestone 2: Correct Destination (40 pts)
    if result_data.get("final_destination_correct", False):
        score += 40
        feedback.append("Good: Destination Charikar is set.")
    else:
        feedback.append("Missing: Final destination is not Charikar.")

    # Milestone 3: Manual Selection Method (30 pts)
    if result_data.get("method_was_manual_selection", False):
        score += 30
        feedback.append("Good: Location selected via map tap.")
    else:
        feedback.append("Issue: Could not confirm map tap selection method.")

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result_data
    }