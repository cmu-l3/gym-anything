#!/usr/bin/env python3
"""
Verifier for check_beta_blocker_with_osimertinib task.

Verification Strategy:
1. File Check: Verify /sdcard/answer.txt exists and contains a valid color.
2. VLM Verification:
   - Check if agent navigated to Osimertinib.
   - Check if agent navigated to Propranolol.
   - Check if the color written in the file matches the color shown on screen.

Points Breakdown:
- Answer file exists and is valid: 20 pts
- VLM: Agent viewed Osimertinib: 20 pts
- VLM: Agent viewed Propranolol interaction: 30 pts
- VLM: Written answer matches screen reality: 30 pts
"""

import json
import tempfile
import os
import logging
import sys

# Add path for local modules if needed
sys.path.append(os.getcwd())

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities from the framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Mock for testing if environment not set up
    def query_vlm(**kwargs): return {"success": False, "error": "ImportError"}
    def sample_trajectory_frames(traj, n): return []
    def get_final_screenshot(traj): return None


def verify_check_beta_blocker_with_osimertinib(traj, env_info, task_info):
    """
    Verify the agent correctly identified the interaction color between Osimertinib and Propranolol.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    valid_colors = metadata.get('valid_colors', ["red", "orange", "yellow", "green", "grey", "gray"])
    
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Retrieve and Parse Result JSON from Device
    # ---------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve task results from device. Did the agent create the output file?"
        }
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ---------------------------------------------------------
    # 2. Analyze File Output (20 points)
    # ---------------------------------------------------------
    answer_exists = result_data.get("answer_exists", False)
    raw_answer = result_data.get("answer_content", "").strip().lower()
    
    # Remove any extra punctuation/whitespace
    clean_answer = ''.join(c for c in raw_answer if c.isalpha())
    
    if answer_exists and clean_answer in valid_colors:
        score += 20
        feedback_parts.append(f"Valid answer file created: '{clean_answer}'")
    elif answer_exists:
        feedback_parts.append(f"Answer file exists but contains invalid color: '{raw_answer}'")
    else:
        feedback_parts.append("Answer file '/sdcard/answer.txt' not found")

    # ---------------------------------------------------------
    # 3. VLM Trajectory Verification (80 points)
    # ---------------------------------------------------------
    frames = sample_trajectory_frames(traj, n=8)  # Sample frames to catch navigation
    final_frame = get_final_screenshot(traj)
    
    # We combine frames for context
    if not frames:
        frames = [final_frame] if final_frame else []
        
    if not frames:
         return {
            "passed": False, 
            "score": score, 
            "feedback": "No screenshots available for verification."
        }

    # Prompt for VLM
    prompt = f"""
    You are verifying an agent's interaction with the 'Liverpool Cancer iChart' app.
    The agent was asked to check the interaction between 'Osimertinib' and 'Propranolol'.
    
    Review the sequence of screenshots and determine:
    1. Did the agent navigate to the cancer drug 'Osimertinib'? (Look for 'Osimertinib' text selected or in header)
    2. Did the agent find 'Propranolol' in the co-medications? (Look for 'Propranolol' text)
    3. Did the agent view a result screen showing a traffic-light color (Red, Orange, Yellow, Green, or Grey)?
    4. What color was the final interaction result displayed on screen?
    
    The agent reported the answer: "{clean_answer}"
    
    Respond in JSON format:
    {{
        "viewed_osimertinib": true/false,
        "viewed_propranolol": true/false,
        "interaction_color_visible": "red/orange/yellow/green/grey/none",
        "reported_answer_matches_screen": true/false
    }}
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # Check 1: Navigated to Osimertinib (20 pts)
        if parsed.get("viewed_osimertinib"):
            score += 20
            feedback_parts.append("VLM confirmed navigation to Osimertinib.")
        else:
            feedback_parts.append("VLM did not see 'Osimertinib' selected.")
            
        # Check 2: Navigated to Propranolol (30 pts)
        if parsed.get("viewed_propranolol"):
            score += 30
            feedback_parts.append("VLM confirmed navigation to Propranolol.")
        else:
            feedback_parts.append("VLM did not see 'Propranolol' selected.")
            
        # Check 3: Answer Match (30 pts)
        # We only award these points if the VLM confirms the screen color matches the user's answer
        screen_color = parsed.get("interaction_color_visible", "none").lower()
        
        # If VLM says it matches, or if screen color matches clean_answer explicitly
        if parsed.get("reported_answer_matches_screen") or (screen_color != "none" and screen_color == clean_answer):
            score += 30
            feedback_parts.append(f"VLM confirmed reported answer '{clean_answer}' matches screen.")
        else:
            feedback_parts.append(f"Mismatch: Screen showed '{screen_color}' but agent reported '{clean_answer}'.")
            
    else:
        feedback_parts.append("VLM verification failed to process images.")

    # ---------------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------------
    # Pass threshold: 70 points (Must have file + basic navigation + some correctness)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }