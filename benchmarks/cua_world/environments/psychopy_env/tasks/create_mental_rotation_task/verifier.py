#!/usr/bin/env python3
"""
Verifier for create_mental_rotation_task.

Scoring Criteria:
1. File exists, valid XML, modified during task (10 pts)
2. Experiment Structure:
   - Has Instructions routine (10 pts)
   - Has Fixation routine (10 pts)
   - Has Trial routine (10 pts)
   - Has End/Thank You routine (5 pts)
3. Trial Logic:
   - At least 2 visual components in trial (for reference + probe) (10 pts)
   - Rotation logic implemented (parameter references angle) (10 pts)
   - Mirror logic implemented (parameter references matchType) (10 pts)
   - Keyboard response accepts keys and uses corrAns (10 pts)
4. Loop Logic:
   - Loop references conditions.csv (15 pts)

Bonus: VLM verification of Builder workflow (used to confirm genuine interaction).
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

def verify_create_mental_rotation_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # Load task result JSON
    # ================================================================
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/task_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # ================================================================
    # Nonce Check
    # ================================================================
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        
        result_nonce = result.get('result_nonce', '')
        if expected_nonce and result_nonce != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "FAIL: Integrity check failed (nonce mismatch)"}
    except:
        pass # If check fails, continue but log warning (or fail if strict)
    finally:
        if 'nonce_path' in locals() and os.path.exists(nonce_path):
            os.unlink(nonce_path)

    # ================================================================
    # Scoring
    # ================================================================
    score = 0
    feedback = []

    # 1. File Basics (10 pts)
    if result.get("file_exists") and result.get("is_valid_xml"):
        if result.get("file_modified"):
            score += 10
            feedback.append("Experiment file created and valid.")
        else:
            score += 5
            feedback.append("Experiment file exists but timestamp suggests it wasn't modified during task.")
    else:
        return {"passed": False, "score": 0, "feedback": "Experiment file not found or invalid XML."}

    # 2. Structure (35 pts total)
    if result.get("has_instructions"):
        score += 10
        feedback.append("Instructions routine present.")
    else:
        feedback.append("Missing Instructions routine.")

    if result.get("has_fixation"):
        score += 10
        feedback.append("Fixation routine present.")
    else:
        feedback.append("Missing Fixation routine.")

    if result.get("has_trial"):
        score += 10
        feedback.append("Trial routine present.")
    else:
        feedback.append("Missing Trial routine.")

    if result.get("has_end"):
        score += 5
        feedback.append("End routine present.")
    
    # 3. Trial Logic (40 pts total)
    # Stimuli
    stim_count = result.get("trial_stimuli_count", 0)
    if stim_count >= 2:
        score += 10
        feedback.append(f"Trial has {stim_count} stimuli (Reference + Probe).")
    elif stim_count == 1:
        score += 5
        feedback.append("Trial has only 1 stimulus (need 2: Reference and Probe).")
    else:
        feedback.append("Trial has no visual stimuli.")

    # Rotation
    if result.get("has_rotation_logic"):
        score += 10
        feedback.append("Rotation logic detected (angle parameter).")
    else:
        feedback.append("Missing rotation logic (parameter linked to angle).")

    # Mirroring
    if result.get("has_mirror_logic"):
        score += 10
        feedback.append("Mirror logic detected (flip/size parameter).")
    else:
        feedback.append("Missing mirror logic (parameter linked to matchType/mirror).")

    # Keyboard
    if result.get("has_keyboard"):
        if result.get("keyboard_uses_corrAns"):
            score += 10
            feedback.append("Keyboard response correctly configured with corrAns.")
        else:
            score += 5
            feedback.append("Keyboard present but missing correct answer variable.")
    else:
        feedback.append("Missing Keyboard response.")

    # 4. Loop Logic (15 pts)
    if result.get("has_loop_referencing_conditions"):
        score += 15
        feedback.append("Loop correctly linked to conditions.csv.")
    else:
        feedback.append("Missing loop or not linked to conditions.csv.")

    # ================================================================
    # VLM Verification (Trajectory) - Optional robustness check
    # ================================================================
    # Note: Main scoring is programmatic. VLM can be used to catch edge cases
    # or ensure they used Builder view. For now, we rely on the file parsing.
    
    final_score = min(score, 100)
    passed = final_score >= 60 and result.get("has_trial") and result.get("has_loop_referencing_conditions")

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " ".join(feedback)
    }