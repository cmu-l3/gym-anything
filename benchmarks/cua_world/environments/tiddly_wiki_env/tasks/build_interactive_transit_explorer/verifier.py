#!/usr/bin/env python3
"""Verifier for build_interactive_transit_explorer task."""

import json
import tempfile
import os
import re

def _check_trajectory_for_gui_interaction(traj):
    """Analyze agent trajectory for evidence of browser GUI interaction.
    Returns (has_mouse_clicks, has_keyboard_input, click_count) tuple.
    """
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


def verify_transit_explorer(traj, env_info, task_info):
    """Verify that the interactive transit explorer tiddler was created correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/transit_explorer_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    text = result.get('tiddler_text', '')

    # Criterion 1: Tiddler exists (10 pts)
    if result.get('tiddler_exists'):
        score += 10
        feedback_parts.append("Tiddler exists")
    else:
        feedback_parts.append("FAIL: Tiddler 'CTA Line Explorer' not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Extract state tiddler for validation checks
    state_tiddler = None
    select_idx = text.find('<$select')
    if select_idx != -1:
        m = re.search(r'tiddler=["\']([^"\']+)["\']', text[select_idx:select_idx+200])
        if m:
            state_tiddler = m.group(1)

    # Criterion 2: Select Widget (20 pts)
    has_select = '<$select' in text
    has_options = all(color in text for color in ['Red', 'Blue', 'Green', 'Brown'])

    if has_select and has_options and state_tiddler:
        score += 20
        feedback_parts.append(f"Dropdown bound to {state_tiddler}")
    elif has_select and has_options:
        score += 10
        feedback_parts.append("Dropdown missing state binding")
    else:
        feedback_parts.append("FAIL: Dropdown missing or incomplete options")

    # Criterion 3: List widget (30 pts)
    has_list = '<$list' in text
    has_contains = 'contains:lines' in text or 'contains:lines[' in text

    uses_state = False
    if state_tiddler and text.count(state_tiddler) >= 2:
        uses_state = True

    if has_list and has_contains and uses_state:
        score += 30
        feedback_parts.append("Dynamic list filter correct")
    elif has_list and has_contains:
        score += 15
        feedback_parts.append("List filter correct but lacks state binding")
    elif has_list:
        score += 5
        feedback_parts.append("List widget found but missing 'contains' filter")
    else:
        feedback_parts.append("FAIL: Missing list widget")

    # Criterion 4: Count widget (20 pts)
    has_count = '<$count' in text
    if has_count and has_contains:
        score += 20
        feedback_parts.append("Count widget correct")
    elif has_count:
        score += 10
        feedback_parts.append("Count widget found but missing filter")
    else:
        feedback_parts.append("FAIL: Missing count widget")

    # Criterion 5: Conditional ADA (20 pts)
    has_ada_text = '(ADA)' in text
    has_ada_field = 'ada-accessible' in text
    has_condition_logic = any(kw in text for kw in ['<$reveal', 'match', '<$list', 'get[ada-accessible]', 'ada-accessible['])

    if has_ada_text and has_ada_field and has_condition_logic:
        score += 20
        feedback_parts.append("ADA conditional logic correct")
    elif has_ada_text:
        score += 5
        feedback_parts.append("ADA text present but logic missing")
    else:
        feedback_parts.append("FAIL: Missing ADA text")

    # Anti-gaming checks
    gui_save = result.get('gui_save_detected', False)
    has_clicks, has_keys, click_count = _check_trajectory_for_gui_interaction(traj)

    if gui_save:
        feedback_parts.append("GUI save verified")
    elif has_clicks or has_keys:
        feedback_parts.append("Trajectory UI interaction verified")
    else:
        feedback_parts.append("Warning: No GUI interaction detected (direct file edit suspected)")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}