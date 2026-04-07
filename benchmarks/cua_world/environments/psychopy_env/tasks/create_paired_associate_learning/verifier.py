#!/usr/bin/env python3
"""
Verifier for create_paired_associate_learning task.

Verification Strategy:
1. File Existence (20 pts): Experiment and CSV exist.
2. CSV Content (10 pts): Valid headers and correct word pairs.
3. Components (35 pts): 
   - TextBox used (20 pts)
   - Code component used (15 pts)
4. Robust Logic (25 pts): Code contains case-insensitive/strip logic.
5. VLM Verification (10 pts): Trajectory shows the task running with visual feedback.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_paired_associate_learning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. File Checks (20 pts)
    if result.get("exp_file_exists") and result.get("exp_file_modified"):
        score += 10
        feedback_parts.append("Experiment file created")
    
    if result.get("csv_file_exists"):
        score += 10
        feedback_parts.append("Conditions file created")
    else:
        feedback_parts.append("Conditions file missing")

    # 2. CSV Content (10 pts)
    csv_headers = result.get("csv_headers", [])
    if "cue" in csv_headers and "target" in csv_headers:
        score += 5
        feedback_parts.append("CSV headers correct")
        
        # Check data count/validity
        if result.get("correct_data_match_count", 0) >= 3:
            score += 5
            feedback_parts.append("CSV data correct")
    else:
        feedback_parts.append(f"Invalid CSV headers: {csv_headers}")

    # 3. Component Usage (35 pts)
    comps = result.get("components", {})
    if comps.get("textbox"):
        score += 20
        feedback_parts.append("TextBox component used")
    else:
        feedback_parts.append("FAIL: No TextBox component found")

    if comps.get("code"):
        score += 15
        feedback_parts.append("Code component used")
    else:
        feedback_parts.append("FAIL: No Code component found")

    # 4. Logic Verification (25 pts)
    code_content = result.get("code_content", {})
    logic_score = 0
    if code_content.get("has_lower"):
        logic_score += 10
        feedback_parts.append("Case-insensitivity logic found (.lower/.upper)")
    if code_content.get("has_strip"):
        logic_score += 5
        feedback_parts.append("Whitespace handling logic found (.strip)")
    if code_content.get("has_if_else"):
        logic_score += 5
        feedback_parts.append("Conditional logic found (if/else)")
    if code_content.get("sets_msg") or code_content.get("sets_color"):
        logic_score += 5
        feedback_parts.append("Feedback response found (msg/color)")
    
    score += logic_score

    # 5. VLM Verification (10 pts)
    # Check if the agent actually RAN the task and saw feedback
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = """
    Analyze these screenshots of a PsychoPy experiment being created and run.
    Look for:
    1. A screen showing two words side-by-side (Study phase).
    2. A screen showing a word and a text input box (Test phase).
    3. Text being typed into the box.
    4. Feedback text like "Correct!" or "Incorrect" appearing.
    
    Did the agent RUN the experiment and receive feedback?
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res.get("success"):
            # Simple heuristic: if VLM is confident about feedback or running
            content = vlm_res.get("parsed", {}).get("content", str(vlm_res)).lower()
            if "feedback" in content or "correct" in content or "run" in content:
                vlm_score = 10
                feedback_parts.append("VLM confirms experiment run")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
    
    score += vlm_score

    # Pass Threshold
    # Must have files, components, and basic logic
    passed = score >= 70 and comps.get("textbox") and comps.get("code")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }