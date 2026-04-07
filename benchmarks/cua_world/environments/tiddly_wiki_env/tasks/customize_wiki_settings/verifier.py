#!/usr/bin/env python3
"""Verifier for customize_wiki_settings task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

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

def verify_customize_settings(traj, env_info, task_info):
    """Verify that the wiki settings (Title, Subtitle, Default Tiddlers) were customized."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_site_title', 'Meridian UX Research Hub')
    expected_subtitle = metadata.get('expected_site_subtitle', 'Research notes and findings for the Meridian Health portal redesign')
    expected_default_tiddlers = metadata.get('expected_default_tiddlers', ['Project Overview', 'Research Plan'])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/customize_settings_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    actual_title = result.get('site_title', '').strip()
    actual_subtitle = result.get('site_subtitle', '').strip()
    actual_default_tiddlers = result.get('default_tiddlers', '')

    # Criterion 1: Site Title (30 pts)
    if actual_title == expected_title:
        score += 30
        feedback_parts.append("Site Title is correct")
    elif actual_title and expected_title.lower() in actual_title.lower():
        score += 15
        feedback_parts.append(f"Site Title partially correct: '{actual_title}'")
    else:
        feedback_parts.append(f"Site Title incorrect: expected '{expected_title}', got '{actual_title}'")

    # Criterion 2: Site Subtitle (30 pts)
    if actual_subtitle == expected_subtitle:
        score += 30
        feedback_parts.append("Site Subtitle is correct")
    elif actual_subtitle and "meridian health" in actual_subtitle.lower():
        score += 15
        feedback_parts.append("Site Subtitle partially correct")
    else:
        feedback_parts.append(f"Site Subtitle incorrect: got '{actual_subtitle}'")

    # Criterion 3: Default Tiddlers (20 pts + 20 pts)
    default_score = 0
    if expected_default_tiddlers[0].lower() in actual_default_tiddlers.lower():
        default_score += 20
        feedback_parts.append(f"Default Tiddlers includes '{expected_default_tiddlers[0]}'")
    else:
        feedback_parts.append(f"Default Tiddlers missing '{expected_default_tiddlers[0]}'")

    if expected_default_tiddlers[1].lower() in actual_default_tiddlers.lower():
        default_score += 20
        feedback_parts.append(f"Default Tiddlers includes '{expected_default_tiddlers[1]}'")
    else:
        feedback_parts.append(f"Default Tiddlers missing '{expected_default_tiddlers[1]}'")

    score += default_score

    # Anti-gaming & Trajectory Analysis
    has_clicks, has_keys, click_count = _check_trajectory_for_gui_interaction(traj)
    gui_save = result.get('gui_save_detected', False)
    modifications = any([
        result.get('title_modified_during_task', False),
        result.get('subtitle_modified_during_task', False),
        result.get('default_tiddlers_modified_during_task', False)
    ])

    if gui_save:
        feedback_parts.append("Settings save verified via GUI logs")
    elif modifications:
        feedback_parts.append("Settings save verified via file modification timestamps")
    else:
        if score > 0:
            feedback_parts.append("WARNING: No explicit file modification detected during task time window")

    if has_clicks or has_keys:
        feedback_parts.append(f"GUI interaction verified ({click_count} clicks)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }