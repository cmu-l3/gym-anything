#!/usr/bin/env python3
"""Verifier for create_tiddler_with_links task."""

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


def verify_create_tiddler_with_links(traj, env_info, task_info):
    """Verify that a new tiddler was created with internal links to existing tiddlers."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', 'RESTful API Design Guide')
    expected_tags = metadata.get('expected_tags', ['Technology', 'API'])
    expected_links = metadata.get('expected_links', ['Agile Methodology Overview', 'Version Control Best Practices'])
    min_word_count = metadata.get('min_word_count', 80)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_links_result.json", temp_file.name)
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

    # Criterion 1: Tiddler exists (5 pts)
    if result.get('tiddler_found'):
        score += 5
        feedback_parts.append("Tiddler found")
    else:
        feedback_parts.append("FAIL: Tiddler not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Title matches (10 pts)
    actual_title = result.get('tiddler_title', '')
    if actual_title.lower() == expected_title.lower():
        score += 10
        feedback_parts.append(f"Title matches: {actual_title}")
    elif expected_title.lower() in actual_title.lower():
        score += 7
        feedback_parts.append(f"Title partial match: {actual_title}")
    else:
        feedback_parts.append(f"Title mismatch: expected '{expected_title}', got '{actual_title}'")

    # Criterion 3: Link to Agile Methodology Overview (10 pts)
    if result.get('has_agile_link'):
        score += 10
        feedback_parts.append("Link to Agile Methodology Overview present")
    else:
        feedback_parts.append("FAIL: Link to Agile Methodology Overview missing")

    # Criterion 4: Link to Version Control Best Practices (10 pts)
    if result.get('has_vcs_link'):
        score += 10
        feedback_parts.append("Link to Version Control Best Practices present")
    else:
        feedback_parts.append("FAIL: Link to Version Control Best Practices missing")

    # Criterion 5: Has any internal links (10 pts)
    link_count = result.get('link_count', 0)
    if link_count >= 2:
        score += 10
        feedback_parts.append(f"Internal links: {link_count}")
    elif link_count >= 1:
        score += 5
        feedback_parts.append(f"Only {link_count} internal link(s)")
    else:
        feedback_parts.append("No internal links found")

    # Criterion 6: Content keywords (10 pts)
    kw_count = 0
    for kw in ['rest', 'api', 'http']:
        if result.get(f'has_{kw}_keyword', False):
            kw_count += 1
    if kw_count >= 3:
        score += 10
        feedback_parts.append(f"All API keywords found ({kw_count}/3)")
    elif kw_count >= 2:
        score += 7
        feedback_parts.append(f"Some API keywords found ({kw_count}/3)")
    elif kw_count >= 1:
        score += 3
        feedback_parts.append(f"Few API keywords ({kw_count}/3)")
    else:
        feedback_parts.append("No API keywords found")

    # Criterion 7: Tags (10 pts)
    tags_found = 0
    if result.get('has_technology_tag'):
        tags_found += 1
    if result.get('has_api_tag'):
        tags_found += 1
    if tags_found == 2:
        score += 10
        feedback_parts.append("Both tags present")
    elif tags_found == 1:
        score += 5
        feedback_parts.append(f"Only {tags_found}/2 tags")
    else:
        feedback_parts.append("Tags missing")

    # Criterion 8: Word count (10 pts)
    word_count = result.get('word_count', 0)
    if word_count >= min_word_count:
        score += 10
        feedback_parts.append(f"Word count OK: {word_count}")
    elif word_count >= min_word_count * 0.5:
        score += 5
        feedback_parts.append(f"Word count low: {word_count}/{min_word_count}")
    else:
        feedback_parts.append(f"Insufficient content: {word_count} words")

    # Criterion 9: GUI interaction verified via server log (25 pts)
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

    feedback_parts.append(f"New tiddler created ({new_count} new)")

    passed = (
        result.get('tiddler_found') and
        new_count > 0 and
        gui_save and
        result.get('has_agile_link') and
        result.get('has_vcs_link') and
        word_count >= min_word_count * 0.5 and
        score >= 55
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
