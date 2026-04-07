#!/usr/bin/env python3
"""Verifier for build_relational_genealogy_tree task."""

import json
import tempfile
import os

def _check_trajectory_for_gui_interaction(traj):
    """Analyze agent trajectory for evidence of browser GUI interaction."""
    mouse_clicks = 0
    keyboard_actions = 0

    if not traj:
        return False, False, 0

    for step in traj:
        action = step.get('action', '') if isinstance(step, dict) else str(step)
        action_lower = action.lower() if isinstance(action, str) else ''

        if any(kw in action_lower for kw in [
            'click', 'mouse_move', 'mouse_click', 'left_click', 'right_click',
            'double_click', 'xdotool mousemove', 'xdotool click',
            'pyautogui.click', 'pyautogui.moveto',
        ]):
            mouse_clicks += 1

        if any(kw in action_lower for kw in [
            'type', 'key', 'xdotool type', 'xdotool key',
            'pyautogui.write', 'pyautogui.press', 'pyautogui.hotkey',
            'keyboard',
        ]):
            keyboard_actions += 1

    return mouse_clicks > 0, keyboard_actions > 0, mouse_clicks


def verify_genealogy_tree(traj, env_info, task_info):
    """Verify that the historical person tiddlers and ViewTemplate were created correctly."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/genealogy_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    expected_data = {
        "Queen Victoria": {"dob": "1819-05-24", "parents": False},
        "Prince Albert": {"dob": "1819-08-26", "parents": False},
        "Victoria, Princess Royal": {"dob": "1840-11-21", "parents": True},
        "Edward VII": {"dob": "1841-11-09", "parents": True},
        "Princess Alice": {"dob": "1843-04-25", "parents": True}
    }

    persons = result.get('persons', {})

    # Criterion 1: Data Tiddlers Created (20 pts)
    # 4 pts per person tiddler that exists AND is tagged Person
    tiddlers_created_pts = 0
    for p_name in expected_data:
        p_info = persons.get(p_name, {})
        if p_info.get('exists'):
            if p_info.get('has_person_tag'):
                tiddlers_created_pts += 4
            else:
                tiddlers_created_pts += 2 # Half points if missing tag
    score += tiddlers_created_pts
    feedback_parts.append(f"Data tiddlers created: {tiddlers_created_pts}/20 pts")

    # Criterion 2: Fields Populated Correctly (20 pts)
    fields_pts = 0
    for p_name, exp in expected_data.items():
        p_info = persons.get(p_name, {})
        if not p_info.get('exists'):
            continue
            
        points_for_this = 0
        # DOB check
        if exp['dob'] in p_info.get('dob', ''):
            points_for_this += 2
            
        # Parents check
        if exp['parents']:
            mother = p_info.get('mother', '')
            father = p_info.get('father', '')
            if 'Queen Victoria' in mother:
                points_for_this += 1
            if 'Prince Albert' in father:
                points_for_this += 1
        else:
            # For Queen/Albert, they shouldn't have mother/father fields (or they can be blank)
            points_for_this += 2

        fields_pts += points_for_this

    score += fields_pts
    feedback_parts.append(f"Fields populated: {fields_pts}/20 pts")

    # Criterion 3: ViewTemplate Exists (15 pts)
    template_found = result.get('template_found', False)
    template_text = result.get('template_text', '')
    
    if template_found:
        score += 15
        feedback_parts.append("ViewTemplate exists")
    else:
        feedback_parts.append("FAIL: ViewTemplate not found")

    # Criterion 4: ViewTemplate Constraints (15 pts)
    constraints_pts = 0
    if template_found:
        text_lower = template_text.lower()
        
        # Check no hardcoded children (10 pts)
        hardcoded = ['edward', 'alice', 'princess royal']
        if not any(h in text_lower for h in hardcoded):
            constraints_pts += 10
            feedback_parts.append("No hardcoded names in template")
        else:
            feedback_parts.append("FAIL: Template contains hardcoded historical names")

        # Check conditional Person targeting (5 pts)
        if 'person' in text_lower and ('tag' in text_lower or 'list' in text_lower):
            constraints_pts += 5
            feedback_parts.append("Template conditionally targets 'Person'")
        else:
            feedback_parts.append("FAIL: Template does not conditionally check for 'Person' tag")
            
    score += constraints_pts

    # Criterion 5: Relational Filter Logic (30 pts)
    logic_pts = 0
    if template_found:
        text_lower = template_text.lower()
        has_field_refs = 'mother' in text_lower or 'father' in text_lower
        
        # Check for dynamic transclusion / reverse lookups
        dynamic_keywords = [
            '<currenttiddler>', '{!!title}', 'listed[', '<storytiddler>',
            '<..currenttiddler>', 'all[current]'
        ]
        has_dynamic_lookup = any(dk in text_lower for dk in dynamic_keywords)
        
        if has_field_refs and has_dynamic_lookup:
            logic_pts += 30
            feedback_parts.append("Dynamic relational filter logic detected")
        elif has_field_refs:
            logic_pts += 15
            feedback_parts.append("Fields referenced in template, but reverse lookup unclear")
        else:
            feedback_parts.append("FAIL: Relational logic missing from template")
            
    score += logic_pts

    # Anti-gaming: GUI usage verification
    gui_save = result.get('gui_save_detected', False)
    has_clicks, _, _ = _check_trajectory_for_gui_interaction(traj)
    if not gui_save and not has_clicks:
        feedback_parts.append("WARNING: No GUI interactions detected, possible CLI gaming")

    passed = score >= 70 and template_found and tiddlers_created_pts >= 10

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }