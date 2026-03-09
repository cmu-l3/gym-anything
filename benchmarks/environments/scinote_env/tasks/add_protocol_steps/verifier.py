#!/usr/bin/env python3
"""Verifier for add_protocol_steps task."""

import json
import tempfile
import os


def verify_add_protocol_steps(traj, env_info, task_info):
    """Verify that protocol steps with content were added to the task."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_step1 = metadata.get('expected_step1_name', 'Prepare Substrate Solutions')
    expected_text_keyword = metadata.get('expected_step1_text_keyword', 'serial dilution')
    expected_step2 = metadata.get('expected_step2_name', 'Record Absorbance Readings')
    expected_checklist = metadata.get('expected_checklist_name', 'Equipment Checklist')
    min_checklist_items = metadata.get('min_checklist_items', 2)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/add_protocol_steps_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    steps = result.get('steps', [])
    initial_count = int(result.get('initial_step_count', 0))
    current_count = int(result.get('current_step_count', 0))

    # Build lookup by name (case-insensitive)
    step_lookup = {}
    for s in steps:
        name = s.get('name', '').strip().lower()
        step_lookup[name] = s

    # Criterion 1 (20 pts): Step 1 exists with correct name
    step1_found = expected_step1.strip().lower() in step_lookup
    if step1_found:
        score += 20
        feedback_parts.append(f"Step '{expected_step1}' found")
    else:
        feedback_parts.append(f"Step '{expected_step1}' not found")

    # Criterion 2 (20 pts): Step 1 has text content containing the keyword
    step1_has_text = False
    if step1_found:
        step1_data = step_lookup[expected_step1.strip().lower()]
        text_content = step1_data.get('text_content', '')
        if expected_text_keyword.lower() in text_content.lower():
            step1_has_text = True
            score += 20
            feedback_parts.append(f"Step 1 text contains '{expected_text_keyword}'")
        else:
            feedback_parts.append(f"Step 1 text missing keyword '{expected_text_keyword}' (got: '{text_content[:100]}')")
    else:
        feedback_parts.append("Cannot check step 1 text (step not found)")

    # Criterion 3 (20 pts): Step 2 exists with correct name
    step2_found = expected_step2.strip().lower() in step_lookup
    if step2_found:
        score += 20
        feedback_parts.append(f"Step '{expected_step2}' found")
    else:
        feedback_parts.append(f"Step '{expected_step2}' not found")

    # Criterion 4 (20 pts): Step 2 has a checklist with correct name and items
    checklist_ok = False
    if step2_found:
        step2_data = step_lookup[expected_step2.strip().lower()]
        checklist_name = step2_data.get('checklist_name', '')
        checklist_count = int(step2_data.get('checklist_item_count', 0))
        if checklist_name.strip().lower() == expected_checklist.strip().lower():
            if checklist_count >= min_checklist_items:
                checklist_ok = True
                score += 20
                feedback_parts.append(f"Checklist '{expected_checklist}' found with {checklist_count} items")
            else:
                score += 10  # partial: checklist exists but insufficient items
                feedback_parts.append(f"Checklist '{expected_checklist}' found but only {checklist_count}/{min_checklist_items} items")
        else:
            feedback_parts.append(f"Checklist name mismatch: expected '{expected_checklist}', got '{checklist_name}'")
    else:
        feedback_parts.append("Cannot check checklist (step 2 not found)")

    passed = step1_found and step1_has_text and step2_found and checklist_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "step1_exists": step1_found,
            "step1_has_text_keyword": step1_has_text,
            "step2_exists": step2_found,
            "step2_has_checklist": checklist_ok
        }
    }
