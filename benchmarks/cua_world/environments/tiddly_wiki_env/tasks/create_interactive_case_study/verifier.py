#!/usr/bin/env python3
"""
Verifier for create_interactive_case_study task in TiddlyWiki.

Uses copy_from_env to read pre-exported verification data from the container.
Also samples VLM trajectory frames to verify visual presence of the UI elements.
"""

import sys
import os
import json
import logging
import tempfile

# Framework utilities
sys.path.insert(0, str(os.path.abspath(os.path.join(os.path.dirname(__file__), '../../'))))
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing an agent's workflow in TiddlyWiki to create an interactive clinical case study.

Look at the provided trajectory screenshots and the final screenshot. Determine the following:
1. Is a tiddler titled "Case Study: Community-Acquired Pneumonia" open and visible in the browser?
2. Are there clickable interactive buttons or reveal elements visible inside the tiddler?
3. Did the agent navigate successfully without leaving error dialogs on screen?

Respond in pure JSON format exactly like this:
{
    "tiddler_visible": true/false,
    "buttons_visible": true/false,
    "no_errors": true/false
}
"""

def verify_create_interactive_case_study(traj, env_info, task_info):
    """
    Verify the clinical case study tiddler meets widget and content requirements.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/case_study_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    max_score = 100
    feedback_parts = []

    # Criterion 1: Tiddler Exists and Anti-gaming checks (10 points total)
    tiddler_exists = result.get('tiddler_exists', False)
    created_during_task = result.get('created_during_task', False)
    body_length = result.get('body_length', 0)

    if not tiddler_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: Tiddler 'Case Study: Community-Acquired Pneumonia' not found."
        }

    score += 5
    feedback_parts.append("Tiddler exists")

    if created_during_task:
        score += 2
        feedback_parts.append("Created during task")
    
    if body_length >= 800:
        score += 3
        feedback_parts.append(f"Content length sufficient ({body_length} chars)")
    else:
        feedback_parts.append(f"Content length short ({body_length} chars)")

    # Criterion 2: Title & Tags Correct (15 points total)
    if result.get('title_match', False):
        score += 5
        feedback_parts.append("Exact title matched")
    else:
        feedback_parts.append(f"Title mismatched: '{result.get('actual_title')}'")

    tags = result.get('tags', '').lower()
    tag_score = 0
    if 'casestudy' in tags: tag_score += 3
    if 'pulmonology' in tags: tag_score += 3
    if 'teaching' in tags: tag_score += 4
    score += tag_score
    if tag_score == 10:
        feedback_parts.append("All tags present")
    else:
        feedback_parts.append(f"Partial/Missing tags (found: {tags})")

    # Criterion 3: Widgets Present (30 points total)
    reveal_count = result.get('reveal_count', 0)
    button_count = result.get('button_count', 0)
    
    if reveal_count >= 4:
        score += 15
        feedback_parts.append(f"Reveal widgets sufficient ({reveal_count})")
    else:
        score += int(15 * (reveal_count / 4))
        feedback_parts.append(f"Missing reveal widgets ({reveal_count}/4)")

    if button_count >= 4:
        score += 15
        feedback_parts.append(f"Button widgets sufficient ({button_count})")
    else:
        score += int(15 * (button_count / 4))
        feedback_parts.append(f"Missing button widgets ({button_count}/4)")

    # Criterion 4: State Tiddler References (10 points total)
    unique_states = result.get('unique_states', 0)
    if unique_states >= 4:
        score += 10
        feedback_parts.append(f"Unique state tiddlers valid ({unique_states})")
    else:
        score += int(10 * (unique_states / 4))
        feedback_parts.append(f"Missing distinct state tiddlers ({unique_states}/4)")

    # Criterion 5: Content Accuracy (32 points total)
    content_pts = 0
    if result.get('has_history_content', False): content_pts += 8
    if result.get('has_exam_content', False): content_pts += 8
    if result.get('has_inv_content', False): content_pts += 8
    if result.get('has_dx_content', False): content_pts += 8
    score += content_pts
    feedback_parts.append(f"Content keyword checks scored {content_pts}/32")

    # Criterion 6: VLM Verification (3 points total)
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=3)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            images = frames + [final_frame]
            vlm_res = query_vlm(images=images, prompt=VLM_PROMPT)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("tiddler_visible", False): vlm_score += 1
                if parsed.get("buttons_visible", False): vlm_score += 1
                if parsed.get("no_errors", False): vlm_score += 1
                feedback_parts.append("VLM visually verified UI elements")
            else:
                feedback_parts.append("VLM query failed, skipped visual bonus")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")

    score += vlm_score

    # Determine passing logic
    # To pass: Total >= 60, AND must have actual widget functionality 
    # (at least 2 reveals and 2 distinct states) + some content.
    key_criteria_met = (reveal_count >= 2) and (unique_states >= 2) and (content_pts >= 16)
    passed = (score >= 60) and key_criteria_met

    if passed:
        feedback_parts.append("SUCCESS: Interactive case study successfully created.")
    else:
        feedback_parts.append("FAILED: Did not meet passing threshold or key widget functionality missing.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }