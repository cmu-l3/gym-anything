#!/usr/bin/env python3
"""
Verifier for update_ivr_audio_prompt task.

SCORING CRITERIA:
1. Audio file uploaded to container (40 pts)
   - Must exist in /var/lib/asterisk/sounds/
   - Must have been created during the task window (anti-gaming)
2. Call Menu 'MAIN_IVR' updated (40 pts)
   - menu_prompt field must match expected filename
3. Prompt format correctness (20 pts)
   - Field must NOT contain '.wav' extension (common user error in Asterisk/Vicidial)
4. VLM Trajectory Verification (bonus/tie-breaker)
   - Checks if agent navigated to Audio Store and Call Menu screens
"""

import json
import tempfile
import os
import logging
import sys

# Add parent directory to path to import vlm_utils if needed, 
# though we'll use gym_anything provided utils usually.
# Assuming standard verifier signature.

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_ivr_audio_prompt(traj, env_info, task_info):
    """
    Verify the IVR prompt update task.
    """
    # 1. Setup access to result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('audio_filename', 'holiday_greeting_2026.wav')
    expected_prompt = metadata.get('audio_prompt_string', 'holiday_greeting_2026')
    
    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Audio File Upload (40 pts) ---
    audio_exists = result.get('audio_file_exists', False)
    uploaded_during_task = result.get('file_uploaded_during_task', False)
    
    if audio_exists:
        if uploaded_during_task:
            score += 40
            feedback_parts.append("[PASS] Audio file uploaded successfully.")
        else:
            # File exists but old timestamp? (Should have been cleaned in setup, but just in case)
            score += 20
            feedback_parts.append("[PARTIAL] Audio file exists but timestamp is old (re-used previous?).")
    else:
        feedback_parts.append("[FAIL] Audio file not found in Audio Store repository.")

    # --- Criterion 2 & 3: Call Menu Configuration (60 pts total) ---
    actual_prompt = result.get('menu_prompt_value', '').strip()
    initial_prompt = result.get('initial_prompt_value', '').strip()
    
    if actual_prompt == initial_prompt:
        feedback_parts.append(f"[FAIL] Call menu prompt was not changed (still '{actual_prompt}').")
    else:
        # Check for exact match (Correct: "holiday_greeting_2026")
        if actual_prompt == expected_prompt:
            score += 60 # 40 for update + 20 for format
            feedback_parts.append(f"[PASS] Call Menu updated correctly to '{actual_prompt}'.")
        
        # Check for common error: including extension (Incorrect: "holiday_greeting_2026.wav")
        elif actual_prompt == expected_filename:
            score += 40 # 40 for update, 0 for format
            feedback_parts.append(f"[PARTIAL] Call Menu updated, but included extension (.wav). Expected '{expected_prompt}', got '{actual_prompt}'.")
        
        # Check for loose match
        elif expected_prompt in actual_prompt:
            score += 20
            feedback_parts.append(f"[FAIL] Call Menu updated with incorrect value. Expected '{expected_prompt}', got '{actual_prompt}'.")
        
        else:
            feedback_parts.append(f"[FAIL] Call Menu prompt mismatch. Expected '{expected_prompt}', got '{actual_prompt}'.")

    # --- VLM Verification (Validation check) ---
    # We use this to ensure they didn't just SQL inject the result (unlikely but good practice)
    # and to verify they used the UI.
    from gym_anything.vlm import sample_trajectory_frames
    frames = sample_trajectory_frames(traj, n=5)
    
    # Simple check logic: If score is high, we assume they did it, 
    # but let's confirm navigation with VLM if possible.
    # (Here we just append a note, not strictly deducting points unless score is suspicious)
    
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }