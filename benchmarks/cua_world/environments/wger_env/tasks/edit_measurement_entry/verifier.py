#!/usr/bin/env python3
"""
Verifier for edit_measurement_entry task.
Checks database differences to ensure the exact measurement entry was updated to 79.5 cm,
while avoiding side-effects (adding new entries or editing wrong records).
Uses VLM trajectory validation for anti-gaming.
"""

import os
import json
import logging
import tempfile

from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if a user successfully completed a UI interaction task in a fitness tracking app.

Please look at this sequence of screenshots and determine:
1. Did the user navigate to the 'Measurements' or 'Body data' section?
2. Did the user select or view the 'Waist' category?
3. Did the user open an edit form for an existing measurement and change the value?

Respond in JSON format:
{
    "navigated_to_measurements": true/false,
    "selected_waist_category": true/false,
    "edited_entry": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_edit_measurement_entry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_value = metadata.get('expected_value', 79.5)
    tolerance = metadata.get('tolerance', 0.05)

    # 1. Load exported state
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

    initial = result.get('initial', {})
    current = result.get('current', {})
    
    if not initial or not current:
        return {"passed": False, "score": 0, "feedback": "Missing initial or current state data."}

    target_id = initial.get('target_id')
    initial_measurements = {m['id']: m for m in initial.get('all_measurements', [])}
    current_measurements = {m['id']: m for m in current.get('all_measurements', [])}

    score = 0
    feedback_parts = []
    
    # 2. Verify Target Entry Modification
    target_entry = current_measurements.get(target_id)
    if target_entry:
        actual_val = target_entry.get('value')
        if abs(actual_val - expected_value) <= tolerance:
            score += 35
            feedback_parts.append(f"Waist entry updated correctly to {actual_val} cm.")
            correct_entry_modified = True
        else:
            feedback_parts.append(f"Target entry has wrong value: {actual_val} cm (expected {expected_value}).")
            correct_entry_modified = False
    else:
        feedback_parts.append("Target entry was deleted instead of edited.")
        correct_entry_modified = False

    # 3. Verify Only the Target Entry Changed
    unintended_edits = 0
    for m_id, m_initial in initial_measurements.items():
        if m_id == target_id:
            continue
        m_current = current_measurements.get(m_id)
        if not m_current or abs(m_initial['value'] - m_current['value']) > 0.001:
            unintended_edits += 1

    if unintended_edits == 0:
        score += 20
        feedback_parts.append("Target entry was the only one modified.")
    else:
        feedback_parts.append(f"Found {unintended_edits} unintended edits to other entries.")

    # 4. Verify Entry Counts (No Additions)
    initial_waist_count = sum(1 for m in initial_measurements.values() if m['category'] == 'Waist')
    current_waist_count = sum(1 for m in current_measurements.values() if m['category'] == 'Waist')
    
    if initial_waist_count == current_waist_count:
        score += 15
        feedback_parts.append("Waist entry count preserved (no new entries added).")
    else:
        feedback_parts.append(f"Waist entry count changed: {initial_waist_count} -> {current_waist_count}.")

    # 5. Verify Other Categories Data Unchanged
    initial_other_count = len(initial_measurements) - initial_waist_count
    current_other_count = len(current_measurements) - current_waist_count
    if initial_other_count == current_other_count:
        score += 10
        feedback_parts.append("Other category entries remained untouched.")
    
    # 6. Verify Category Count Preserved
    categories_count = current.get('categories_count', 0)
    if categories_count == 3:
        score += 5
        feedback_parts.append("Measurement category count preserved.")
        
    # 7. VLM Verification (Trajectory Analysis)
    if query_vlm and traj:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_response = query_vlm(images=frames, prompt=VLM_PROMPT)
            parsed = vlm_response.get('parsed', {})
            
            navigated = parsed.get("navigated_to_measurements", False)
            selected = parsed.get("selected_waist_category", False)
            edited = parsed.get("edited_entry", False)
            
            if navigated and selected and edited:
                score += 15
                feedback_parts.append("VLM confirms UI interaction workflow.")
            else:
                feedback_parts.append(f"VLM missing workflow steps. Reason: {parsed.get('reasoning', 'None')}")
        else:
            feedback_parts.append("No trajectory frames for VLM verification.")

    passed = (score >= 60) and correct_entry_modified

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }