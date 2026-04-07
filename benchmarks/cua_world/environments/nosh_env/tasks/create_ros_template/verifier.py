#!/usr/bin/env python3
"""
Verifier for create_ros_template task.

Verifies:
1. Template "Cardio_Consult" exists in the database.
2. Template contains the 5 required symptom categories/items.
3. Template was created during the task (not pre-existing).
4. VLM trajectory confirms UI interaction.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_ros_template(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    max_score = 100
    feedback_parts = []
    
    # Criterion 1: Template Existence (40 pts)
    # Must be a NEW record (anti-gaming)
    template_exists = result.get('template_exists', False)
    is_new = result.get('is_new_record', True)
    
    if template_exists:
        if is_new:
            score += 40
            feedback_parts.append("Template 'Cardio_Consult' created successfully")
        else:
            score += 20
            feedback_parts.append("Template exists but appears pre-existing (did you create a new one?)")
    else:
        feedback_parts.append("Template 'Cardio_Consult' NOT found in database")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Content Check (50 pts total)
    items = result.get('items_found', {})
    
    item_scores = {
        "fatigue": 10,
        "chest_pain": 10,
        "palpitations": 10,
        "edema": 10,
        "shortness_of_breath": 10
    }
    
    items_found_count = 0
    for item, points in item_scores.items():
        if items.get(item, False):
            score += points
            items_found_count += 1
        else:
            feedback_parts.append(f"Missing item: {item.replace('_', ' ')}")
            
    if items_found_count == 5:
        feedback_parts.append("All required symptoms present")

    # Criterion 3: VLM Trajectory Verification (10 pts)
    # Verify the agent actually navigated the configuration menus
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review the screenshots of an agent using an EHR system (NOSH).
    Did the agent navigate to an 'Administration', 'Settings', or 'Templates' configuration screen?
    Is there evidence of creating or editing a form/template?
    
    Answer YES or NO with a brief reason.
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    
    vlm_passed = False
    if vlm_result and isinstance(vlm_result, dict):
        response_text = vlm_result.get('response', '').upper()
        if 'YES' in response_text:
            score += 10
            vlm_passed = True
            feedback_parts.append("VLM confirms configuration workflow")
        else:
            feedback_parts.append("VLM could not verify navigation to settings")
    
    # Pass logic
    # Need template created + at least 3 items correct
    passed = (template_exists and is_new and items_found_count >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }