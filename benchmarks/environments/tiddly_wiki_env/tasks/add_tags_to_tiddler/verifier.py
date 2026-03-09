#!/usr/bin/env python3
"""Verifier for add_tags_to_tiddler task."""

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


def verify_add_tags(traj, env_info, task_info):
    """Verify that new tags were added to an existing tiddler."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    new_tags = metadata.get('new_tags', ['Biotechnology', 'Nobel'])
    existing_tags = metadata.get('existing_tags', ['Science', 'Biology', 'Genetics'])
    all_expected = metadata.get('all_expected_tags', existing_tags + new_tags)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/add_tags_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Tiddler still exists (5 pts - low value since it exists by default)
    if result.get('tiddler_exists'):
        score += 5
        feedback_parts.append("Tiddler exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Tiddler was deleted or not found"}

    # Criterion 2: Biotechnology tag added (20 pts - primary objective)
    if result.get('has_biotechnology_tag'):
        score += 20
        feedback_parts.append("Biotechnology tag added")
    else:
        feedback_parts.append("FAIL: Biotechnology tag not found")

    # Criterion 3: Nobel tag added (20 pts - primary objective)
    if result.get('has_nobel_tag'):
        score += 20
        feedback_parts.append("Nobel tag added")
    else:
        feedback_parts.append("FAIL: Nobel tag not found")

    # Criterion 4: Existing tags preserved (10 pts)
    existing_preserved = 0
    for tag_name in existing_tags:
        key = f"has_{tag_name.lower()}_tag"
        if result.get(key, False):
            existing_preserved += 1
    if existing_preserved == len(existing_tags):
        score += 10
        feedback_parts.append(f"All {existing_preserved} existing tags preserved")
    elif existing_preserved > 0:
        score += 5
        feedback_parts.append(f"Only {existing_preserved}/{len(existing_tags)} existing tags preserved")
    else:
        feedback_parts.append("FAIL: Existing tags were removed")

    # Criterion 5: Content preserved (10 pts)
    if result.get('content_preserved') and result.get('content_word_count', 0) > 50:
        score += 10
        feedback_parts.append("Content preserved")
    elif result.get('content_preserved'):
        score += 5
        feedback_parts.append("Content partially preserved")
    else:
        feedback_parts.append("FAIL: Original content was lost")

    # Criterion 6: Total tag count reflects additions (10 pts)
    tag_count = result.get('tag_count', 0)
    if tag_count >= 5:
        score += 10
        feedback_parts.append(f"Total tags: {tag_count}")
    elif tag_count >= 4:
        score += 5
        feedback_parts.append(f"Tag count: {tag_count}")
    else:
        feedback_parts.append(f"Insufficient tags: {tag_count}")

    # Criterion 7: GUI interaction verified via server log (25 pts)
    gui_save = result.get('gui_save_detected', False)
    if gui_save:
        score += 25
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
        result.get('tiddler_exists') and
        result.get('has_biotechnology_tag') and
        result.get('has_nobel_tag') and
        gui_save and
        existing_preserved >= 2 and
        result.get('content_preserved') and
        score >= 60
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
