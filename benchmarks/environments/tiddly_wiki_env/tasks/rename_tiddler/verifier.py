#!/usr/bin/env python3
"""Verifier for rename_tiddler task."""

import json
import tempfile
import os


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


def verify_rename_tiddler(traj, env_info, task_info):
    """Verify that a tiddler was renamed while preserving content and tags."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    original_title = metadata.get('original_title', 'Q1 2024 Product Roadmap')
    new_title = metadata.get('new_title', 'Q1 2024 Engineering Roadmap')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/rename_tiddler_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: New title tiddler exists (20 pts)
    if result.get('new_exists'):
        score += 20
        feedback_parts.append("New title tiddler exists")
    else:
        feedback_parts.append("FAIL: New title tiddler not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Original title removed (20 pts - properly penalizes copy-not-rename)
    if not result.get('original_exists'):
        score += 20
        feedback_parts.append("Original title removed")
    else:
        feedback_parts.append("FAIL: Original title still exists (copy instead of rename)")

    # Criterion 3: Tags preserved (15 pts)
    tags_preserved = 0
    if result.get('has_roadmap_tag'):
        tags_preserved += 1
    if result.get('has_pm_tag'):
        tags_preserved += 1
    if result.get('has_q1_tag'):
        tags_preserved += 1

    if tags_preserved == 3:
        score += 15
        feedback_parts.append("All tags preserved")
    elif tags_preserved >= 2:
        score += 10
        feedback_parts.append(f"Tags partially preserved: {tags_preserved}/3")
    elif tags_preserved >= 1:
        score += 5
        feedback_parts.append(f"Few tags preserved: {tags_preserved}/3")
    else:
        feedback_parts.append("FAIL: Tags lost during rename")

    # Criterion 4: Content preserved (20 pts)
    content_keywords = 0
    if result.get('content_has_api'):
        content_keywords += 1
    if result.get('content_has_dashboard'):
        content_keywords += 1
    if result.get('content_has_sprint'):
        content_keywords += 1

    new_wc = result.get('new_word_count', 0)
    orig_wc = result.get('original_word_count', 0)

    if content_keywords >= 2 and new_wc > 50:
        score += 20
        feedback_parts.append(f"Content preserved ({new_wc} words, {content_keywords} keywords)")
    elif content_keywords >= 1 and new_wc > 20:
        score += 10
        feedback_parts.append(f"Content partially preserved ({new_wc} words)")
    else:
        feedback_parts.append(f"FAIL: Content appears lost ({new_wc} words, {content_keywords} keywords)")

    # Criterion 5: Word count roughly matches original (5 pts)
    if orig_wc > 0 and new_wc > 0:
        ratio = new_wc / orig_wc
        if 0.7 <= ratio <= 1.3:
            score += 5
            feedback_parts.append("Word count consistent with original")
        elif 0.5 <= ratio <= 1.5:
            score += 3
            feedback_parts.append(f"Word count differs: {new_wc} vs {orig_wc} original")
        else:
            feedback_parts.append(f"Word count diverges: {new_wc} vs {orig_wc} original")
    elif new_wc > 50:
        score += 3
        feedback_parts.append(f"Content present ({new_wc} words)")

    # Criterion 6: GUI interaction verified via server log (20 pts)
    gui_save = result.get('gui_save_detected', False)
    if gui_save:
        score += 20
        feedback_parts.append("GUI save verified via server log")
    else:
        feedback_parts.append("FAIL: No server-mediated save detected (direct file edit suspected)")

    # Trajectory analysis (informational)
    has_clicks, has_keys, click_count = _check_trajectory_for_gui_interaction(traj)
    if has_clicks or has_keys:
        feedback_parts.append(f"Trajectory shows GUI interaction ({click_count} clicks)")
    else:
        feedback_parts.append("WARNING: No GUI interaction found in trajectory")

    passed = (
        result.get('new_exists') and
        not result.get('original_exists') and
        gui_save and
        content_keywords >= 2 and
        tags_preserved >= 2 and
        score >= 60
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
