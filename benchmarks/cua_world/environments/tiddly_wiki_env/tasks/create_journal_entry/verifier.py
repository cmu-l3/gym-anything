#!/usr/bin/env python3
"""Verifier for create_journal_entry task."""

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


def verify_create_journal(traj, env_info, task_info):
    """Verify that a journal entry was created with appropriate content."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tag = metadata.get('expected_tag', 'Journal')
    min_word_count = metadata.get('min_word_count', 50)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_journal_result.json", temp_file.name)
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

    # Criterion 1: Journal tiddler found (15 pts)
    if result.get('journal_found'):
        score += 15
        feedback_parts.append("Journal tiddler found")
    else:
        feedback_parts.append("FAIL: No journal tiddler found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Has Journal tag (15 pts)
    if result.get('has_journal_tag'):
        score += 15
        feedback_parts.append("Journal tag present")
    else:
        feedback_parts.append("FAIL: Journal tag missing")

    # Criterion 3: Title contains date (15 pts)
    if result.get('has_date_in_title'):
        score += 15
        feedback_parts.append(f"Date in title: {result.get('journal_title', '')}")
    else:
        feedback_parts.append(f"FAIL: No date in title: {result.get('journal_title', '')}")

    # Criterion 4: Content word count (15 pts)
    word_count = result.get('word_count', 0)
    if word_count >= min_word_count:
        score += 15
        feedback_parts.append(f"Word count OK: {word_count} words")
    elif word_count >= min_word_count * 0.5:
        score += 8
        feedback_parts.append(f"Word count low: {word_count}/{min_word_count}")
    elif word_count > 10:
        score += 3
        feedback_parts.append(f"Word count very low: {word_count}/{min_word_count}")
    else:
        feedback_parts.append(f"Insufficient content: {word_count} words")

    # Criterion 5: Today's date matches (10 pts)
    today = result.get('today_date', '')  # format: YYYYMMDD e.g. 20260211
    title = result.get('journal_title', '')
    today_match = False
    if today and len(today) == 8:
        year = today[:4]
        month = today[4:6]
        day = today[6:8]
        day_no_zero = day.lstrip('0')
        if year in title and (day in title or day_no_zero in title):
            today_match = True
        elif today in title:
            today_match = True
    if today_match:
        score += 10
        feedback_parts.append("Today's date in title")
    else:
        feedback_parts.append("Title may not have today's date")

    # Criterion 6: GUI interaction verified via server log (20 pts)
    gui_save = result.get('gui_save_detected', False)
    if gui_save:
        score += 20
        feedback_parts.append("GUI save verified via server log")
    else:
        feedback_parts.append("FAIL: No server-mediated save detected (direct file edit suspected)")

    # Criterion 7: New tiddler count (10 pts)
    if new_count > 0:
        score += 10
        feedback_parts.append(f"New tiddler created ({new_count} new)")
    else:
        feedback_parts.append("WARNING: No new tiddler file detected")

    # Trajectory analysis (informational)
    has_clicks, has_keys, click_count = _check_trajectory_for_gui_interaction(traj)
    if has_clicks or has_keys:
        feedback_parts.append(f"Trajectory shows GUI interaction ({click_count} clicks)")
    else:
        feedback_parts.append("WARNING: No GUI interaction found in trajectory")

    passed = (
        result.get('journal_found') and
        new_count > 0 and
        gui_save and
        result.get('has_journal_tag') and
        result.get('has_date_in_title') and
        word_count >= min_word_count * 0.5 and
        score >= 55
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
