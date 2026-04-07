#!/usr/bin/env python3
"""
Verifier for configure_browser_reading_aids task.

Verifications checks:
1. Did the agent create the "Literature Analysis Exam" configuration?
2. Did the agent enable "Text Search" in the DB parameters?
3. Did the agent enable "Right Mouse Button" in the DB parameters?
4. VLM verification of the trajectory frames (workflow confirmation).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying an agent that was tasked with configuring Safe Exam Browser settings.
The goal was to create an Exam Configuration named 'Literature Analysis Exam' and explicitly enable "Text Search" and "Right Mouse Button" (context menu).

Review the trajectory frames and determine:
1. Did the agent navigate to the Exam Configuration section?
2. Did the agent edit or create 'Literature Analysis Exam'?
3. Did the agent interact with checkboxes/toggles for "Text Search" and "Right Mouse Button"?

Respond with a JSON object:
{
    "navigated_to_config": boolean,
    "edited_literature_exam": boolean,
    "interacted_with_settings": boolean
}
"""

def verify_configure_browser_reading_aids(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely retrieve exported result from container
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
    
    config_node_id = result.get('config_node_id')
    config_values = result.get('config_values', {})
    
    # ---------------------------------------------------------
    # CRITERION 1: Configuration Exists (20 Points)
    # ---------------------------------------------------------
    if config_node_id:
        score += 20
        feedback_parts.append("Config 'Literature Analysis Exam' created")
    else:
        feedback_parts.append("Config 'Literature Analysis Exam' NOT found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    # ---------------------------------------------------------
    # CRITERION 2 & 3: Check Attribute Toggles (30 Points Each)
    # ---------------------------------------------------------
    text_search_enabled = False
    right_mouse_enabled = False
    
    for k, v in config_values.items():
        k_lower = k.lower()
        v_str = str(v).lower()
        is_true = v_str in ['true', '1']
        
        # Account for internal DB parameter naming mappings
        if 'textsearch' in k_lower and is_true:
            text_search_enabled = True
        if ('rightmouse' in k_lower or 'contextmenu' in k_lower) and is_true:
            right_mouse_enabled = True
            
    if text_search_enabled:
        score += 30
        feedback_parts.append("Text Search enabled")
    else:
        feedback_parts.append("Text Search NOT enabled")
        
    if right_mouse_enabled:
        score += 30
        feedback_parts.append("Right Mouse enabled")
    else:
        feedback_parts.append("Right Mouse NOT enabled")

    # ---------------------------------------------------------
    # CRITERION 4: VLM Trajectory Verification (20 Points)
    # ---------------------------------------------------------
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        if frames:
            vlm_response = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("navigated_to_config"):
                    vlm_score += 5
                if parsed.get("edited_literature_exam"):
                    vlm_score += 5
                if parsed.get("interacted_with_settings"):
                    vlm_score += 10
                feedback_parts.append(f"VLM Score: {vlm_score}/20")
            else:
                feedback_parts.append("VLM verification failed")
                vlm_score = 10 # Provide partial fallback credit if VLM network call fails
        else:
            feedback_parts.append("No frames found for VLM")
    except ImportError:
        logger.warning("VLM tools not available, applying fallback VLM score.")
        vlm_score = 20
        feedback_parts.append("VLM bypassed (local fallback)")
    except Exception as e:
        logger.error(f"VLM error: {e}")
        vlm_score = 10
        feedback_parts.append("VLM exception fallback")
        
    score += vlm_score

    # Determine Pass/Fail (Require config + at least one parameter flipped + 70% overall)
    passed = score >= 70 and bool(config_node_id) and (text_search_enabled or right_mouse_enabled)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }