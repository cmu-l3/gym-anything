#!/usr/bin/env python3
"""Verifier for create_tiddler task."""

import json
import tempfile
import os


def _check_trajectory_for_gui_interaction(traj):
    """Analyze agent trajectory for evidence of browser GUI interaction.

    Returns (has_mouse_clicks, has_keyboard_input, click_count) tuple.
    Checks for mouse click actions and keyboard typing that indicate
    the agent interacted with the browser rather than using terminal commands.
    """
    mouse_clicks = 0
    keyboard_actions = 0

    if not traj:
        return False, False, 0

    for step in traj:
        action = step.get('action', '') if isinstance(step, dict) else str(step)
        action_lower = action.lower() if isinstance(action, str) else ''

        # Check for mouse click actions (common CUA/pyautogui patterns)
        if any(kw in action_lower for kw in [
            'click', 'mouse_move', 'mouse_click', 'left_click', 'right_click',
            'double_click', 'xdotool mousemove', 'xdotool click',
            'pyautogui.click', 'pyautogui.moveto',
        ]):
            mouse_clicks += 1

        # Check for keyboard typing actions
        if any(kw in action_lower for kw in [
            'type', 'key', 'xdotool type', 'xdotool key',
            'pyautogui.write', 'pyautogui.press', 'pyautogui.hotkey',
            'keyboard',
        ]):
            keyboard_actions += 1

    return mouse_clicks > 0, keyboard_actions > 0, mouse_clicks


def verify_create_tiddler(traj, env_info, task_info):
    """Verify that a new tiddler was created with correct title, content, and tags."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', 'Machine Learning Pipeline Architecture')
    expected_tags = metadata.get('expected_tags', ['Technology', 'MachineLearning'])
    min_word_count = metadata.get('min_word_count', 100)
    expected_keywords = metadata.get('expected_keywords', ['data', 'model', 'training', 'pipeline'])

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_tiddler_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 0: New tiddler was actually created (anti-gaming)
    new_count = result.get('current_count', 0) - result.get('initial_count', 0)
    if new_count <= 0:
        feedback_parts.append("FAIL: No new tiddler file created")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 1: Tiddler exists (10 pts)
    if result.get('tiddler_found'):
        score += 10
        feedback_parts.append("Tiddler found")
    else:
        feedback_parts.append("FAIL: Tiddler not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Title matches (10 pts)
    actual_title = result.get('tiddler_title', '')
    if actual_title.lower() == expected_title.lower():
        score += 10
        feedback_parts.append(f"Title matches: {actual_title}")
    elif expected_title.lower() in actual_title.lower() or actual_title.lower() in expected_title.lower():
        score += 7
        feedback_parts.append(f"Title partial match: {actual_title}")
    else:
        feedback_parts.append(f"Title mismatch: expected '{expected_title}', got '{actual_title}'")

    # Criterion 3: Word count meets minimum (15 pts)
    word_count = result.get('word_count', 0)
    if word_count >= min_word_count:
        score += 15
        feedback_parts.append(f"Word count OK: {word_count} words")
    elif word_count >= min_word_count * 0.5:
        score += 8
        feedback_parts.append(f"Word count low: {word_count}/{min_word_count}")
    else:
        feedback_parts.append(f"Word count too low: {word_count}/{min_word_count}")

    # Criterion 4: Contains expected keywords (10 pts)
    keywords_found = 0
    for kw in expected_keywords:
        key = f"has_{kw}_keyword"
        if result.get(key, False):
            keywords_found += 1
    if keywords_found == len(expected_keywords):
        score += 10
        feedback_parts.append(f"All {keywords_found} keywords found")
    elif keywords_found >= len(expected_keywords) // 2:
        score += 5
        feedback_parts.append(f"Keywords: {keywords_found}/{len(expected_keywords)}")
    else:
        feedback_parts.append(f"Keywords missing: {keywords_found}/{len(expected_keywords)}")

    # Criterion 5: Has Technology tag (10 pts)
    if result.get('has_technology_tag'):
        score += 10
        feedback_parts.append("Technology tag present")
    else:
        feedback_parts.append("FAIL: Technology tag missing")

    # Criterion 6: Has MachineLearning tag (10 pts)
    if result.get('has_ml_tag'):
        score += 10
        feedback_parts.append("MachineLearning tag present")
    else:
        feedback_parts.append("FAIL: MachineLearning tag missing")

    # Criterion 7: Has formatting (10 pts)
    if result.get('has_formatting'):
        score += 10
        feedback_parts.append("TiddlyWiki formatting used")
    else:
        feedback_parts.append("No TiddlyWiki formatting detected")

    # Criterion 8: GUI interaction verified via server log (25 pts)
    # TiddlyWiki server logs "Dispatching 'save' task:" for saves via web UI/REST API
    # Direct .tid file edits do NOT trigger this log entry
    gui_save = result.get('gui_save_detected', False)
    if gui_save:
        score += 25
        feedback_parts.append("GUI save verified via server log")
    else:
        feedback_parts.append("FAIL: No server-mediated save detected (direct file edit suspected)")

    # Trajectory analysis (informational - logged for audit but not scored separately
    # since gui_save_detected already gates against direct file manipulation)
    has_clicks, has_keys, click_count = _check_trajectory_for_gui_interaction(traj)
    if has_clicks or has_keys:
        feedback_parts.append(f"Trajectory shows GUI interaction ({click_count} clicks)")
    else:
        feedback_parts.append("WARNING: No GUI interaction found in trajectory")

    feedback_parts.append(f"New tiddlers created: {new_count}")

    # Pass requires: new tiddler + tiddler found + at least one tag + sufficient content + server save
    passed = (
        result.get('tiddler_found') and
        new_count > 0 and
        gui_save and
        score >= 60 and
        (result.get('has_technology_tag') or result.get('has_ml_tag')) and
        word_count >= min_word_count * 0.5
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
