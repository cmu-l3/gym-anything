#!/usr/bin/env python3
"""
Verifier for Reading Practice Activity Task.

Verifies:
1. Log file creation and content (programmatic)
2. Navigation and gameplay interaction (VLM trajectory analysis)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reading_practice(traj, env_info, task_info):
    """
    Verify the agent completed the reading practice activity.
    """
    # 0. Setup and Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load programmatic result
    task_result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. File Verification (30 points total)
    score_file = 0
    feedback_file = []
    
    log_exists = task_result.get("log_exists", False)
    log_fresh = task_result.get("log_created_during_task", False)
    line_count = int(task_result.get("log_line_count", 0))
    preview = task_result.get("log_content_preview", "").replace("|", ", ")

    if log_exists and log_fresh:
        score_file += 15
        feedback_file.append("Log file created.")
        
        # Check content validity
        if line_count >= 5:
            score_file += 15
            feedback_file.append(f"Log contains sufficient entries ({line_count} words).")
        elif line_count > 0:
            score_file += 5
            feedback_file.append(f"Log contains some entries ({line_count}), but fewer than required 5.")
        else:
            feedback_file.append("Log file is empty.")
            
        # Basic sanity check on content (avoiding 'Word 1', 'Word 2' placeholders)
        # Real GCompris words are typically lowercase nouns like 'ball', 'apple'
        if "word" in preview.lower() and "1" in preview:
            score_file -= 10 # Penalty for likely placeholder text
            feedback_file.append("Warning: Log content looks suspicious/synthetic.")
    else:
        feedback_file.append("Log file not created or not modified during task.")

    # 2. VLM Trajectory Verification (70 points total)
    # We sample frames to see navigation and gameplay
    frames = sample_trajectory_frames(traj, n=6)
    
    prompt = f"""
    You are verifying an educational software task. The agent was asked to:
    1. Open GCompris.
    2. Navigate to the 'Reading' category.
    3. Open the 'Reading practice' activity (usually shows a word and matching images).
    4. Play the game by matching words to images for at least 5 words.
    
    Attached are screenshots from the agent's session.
    
    Please answer the following in JSON format:
    {{
        "activity_launched": boolean, // Did they find and open the 'Reading practice' activity?
        "gameplay_visible": boolean, // Do you see the specific interface with a target word and selectable images?
        "progress_detected": boolean, // Does the target word or image set change between frames?
        "success_state": boolean, // Is there a 'congratulations', star, or level complete animation?
        "words_seen": [list of strings], // List any target words you can read from the screen
        "reasoning": "string"
    }}
    """
    
    vlm_response = query_vlm(images=frames, prompt=prompt)
    
    score_vlm = 0
    feedback_vlm = []
    
    if vlm_response and vlm_response.get("success"):
        data = vlm_response.get("parsed", {})
        
        if data.get("activity_launched"):
            score_vlm += 20
            feedback_vlm.append("Activity launched successfully.")
        else:
            feedback_vlm.append("Could not verify activity launch.")

        if data.get("gameplay_visible"):
            score_vlm += 10 # Bonus for clear visibility
            if data.get("progress_detected"):
                score_vlm += 20
                feedback_vlm.append("Gameplay progress detected (words changing).")
            else:
                feedback_vlm.append("Gameplay visible but no progress detected.")
        
        if data.get("success_state"):
            score_vlm += 20
            feedback_vlm.append("Level completion/success animation observed.")
            
        # Cross-reference VLM words with log file if possible
        vlm_words = [w.lower() for w in data.get("words_seen", [])]
        if vlm_words and log_exists:
            feedback_vlm.append(f"VLM identified words: {', '.join(vlm_words)}")

    else:
        feedback_vlm.append("VLM analysis failed to return valid data.")

    # Final Scoring
    total_score = score_file + score_vlm
    passed = total_score >= 70
    
    feedback_str = f"File: {' '.join(feedback_file)} | VLM: {' '.join(feedback_vlm)}"

    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback_str,
        "details": {
            "file_score": score_file,
            "vlm_score": score_vlm,
            "log_preview": preview
        }
    }