#!/usr/bin/env python3
"""
Verifier for reorder_tagged_tiddlers task.

Verification Strategy:
1. PRIMARY: Analyze exported JSON representing the TiddlyWiki API response for the `IncidentResponse` tiddler.
2. Check list field existence, content, and ordering.
3. Check body text for macro and word count.
4. Check tags for 'Runbook'.
5. VLM FALLBACK/TRAJECTORY: Verify GUI interaction via trajectory logs and screenshot.
"""

import json
import os
import re
import tempfile
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
            'xdotool mousemove', 'xdotool click', 'pyautogui.click'
        ]):
            mouse_clicks += 1

        if any(kw in action_lower for kw in [
            'type', 'key', 'xdotool type', 'xdotool key', 'pyautogui.write', 'keyboard'
        ]):
            keyboard_actions += 1

    return mouse_clicks > 0, keyboard_actions > 0, mouse_clicks


def verify_reorder_tiddlers(traj, env_info, task_info):
    """Verify that IncidentResponse tiddler was created with correct list ordering."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected metadata
    metadata = task_info.get('metadata', {})
    expected_order = metadata.get('expected_order', [
        "Incident Detection and Alerting",
        "Initial Triage and Assessment",
        "Communication and Escalation",
        "Containment and Mitigation",
        "Recovery and Restoration",
        "Post-Incident Review"
    ])
    
    # Load result from environment
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

    score = 0
    max_score = 100
    feedback_parts = []

    tiddler_exists = result.get('tiddler_exists', False)
    mtime = result.get('mtime', 0)
    task_start = result.get('task_start', 0)
    tiddler_data = result.get('tiddler_data', {})

    # Criterion 1: Tiddler exists and created during task (10 pts)
    if tiddler_exists:
        if mtime >= task_start:
            score += 10
            feedback_parts.append("IncidentResponse tiddler created during task")
        else:
            feedback_parts.append("WARNING: Tiddler existed before task start (possible gaming)")
            # No points if created before task, but let verification continue
    else:
        feedback_parts.append("FAIL: IncidentResponse tiddler not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: List field present & Criterion 3: All 6 titles present & Criterion 4: Correct exact order
    list_field = tiddler_data.get('list', '')
    
    if list_field:
        score += 10  # List field present
        feedback_parts.append("List field present")
        
        # TiddlyWiki API might return list as a list of strings OR a raw string
        parsed_list = []
        if isinstance(list_field, list):
            parsed_list = list_field
        elif isinstance(list_field, str):
            # Parse double brackets
            matches = re.findall(r'\[\[(.*?)\]\]', list_field)
            if matches:
                parsed_list = matches
            else:
                # Fallback space parsing if they didn't use brackets (though multi-word needs brackets)
                parsed_list = [t for t in list_field.split() if t]

        # Check titles present (15 pts)
        titles_found = sum(1 for title in expected_order if title in parsed_list or any(title in p for p in parsed_list))
        
        if titles_found == len(expected_order):
            score += 15
            feedback_parts.append(f"All {len(expected_order)} procedure titles found in list")
        elif titles_found > 0:
            partial = int((titles_found / len(expected_order)) * 15)
            score += partial
            feedback_parts.append(f"Partial titles found: {titles_found}/{len(expected_order)} ({partial} pts)")
        else:
            feedback_parts.append("FAIL: No expected procedure titles found in list")

        # Check exact ordering (25 pts)
        # Verify the parsed list exactly matches the expected sequence
        # We only look at elements that are in our expected list, ignoring extraneous tags
        filtered_extracted = [item for item in parsed_list if item in expected_order]
        
        if filtered_extracted == expected_order:
            score += 25
            feedback_parts.append("Exact correct incident handling sequence verified")
        elif len(filtered_extracted) > 1:
            # Check how many are in the exact absolute position
            correct_pos = sum(1 for i, item in enumerate(filtered_extracted) if i < len(expected_order) and item == expected_order[i])
            partial = int((correct_pos / len(expected_order)) * 25)
            score += partial
            feedback_parts.append(f"Partial sequence order match: {correct_pos}/{len(expected_order)} in correct position ({partial} pts)")
        else:
            feedback_parts.append("FAIL: Sequence order is incorrect or unparseable")
    else:
        feedback_parts.append("FAIL: List field is missing")

    # Extract text and tags
    body_text = tiddler_data.get('text', '')
    tags_field = tiddler_data.get('tags', [])
    if isinstance(tags_field, str):
        tags_field = [t for t in tags_field.split() if t]

    # Criterion 5: Body contains <<list-links>> (15 pts)
    if '<<list-links>>' in body_text:
        score += 15
        feedback_parts.append("Macro <<list-links>> found in body")
    elif 'list-links' in body_text.lower():
        score += 8
        feedback_parts.append("Macro list-links found but syntax incorrect")
    else:
        feedback_parts.append("FAIL: Macro <<list-links>> not found")

    # Criterion 6: Overview text >= 20 words (10 pts)
    # Strip the macro itself to accurately count words
    clean_text = re.sub(r'<<.*?>>', '', body_text).strip()
    words = clean_text.split()
    word_count = len(words)
    
    if word_count >= 20:
        score += 10
        feedback_parts.append(f"Overview text present ({word_count} words)")
    elif word_count > 5:
        score += 5
        feedback_parts.append(f"Overview text too short ({word_count}/20 words)")
    else:
        feedback_parts.append("FAIL: Insufficient overview text")

    # Criterion 7: Tagged with Runbook (10 pts)
    if 'Runbook' in tags_field or any('runbook' in t.lower() for t in tags_field):
        score += 10
        feedback_parts.append("Tagged with 'Runbook'")
    else:
        feedback_parts.append("FAIL: 'Runbook' tag missing")

    # Criterion 8: GUI interaction/trajectory logic (5 pts)
    gui_save = result.get('gui_save_detected', False)
    has_clicks, has_keys, click_count = _check_trajectory_for_gui_interaction(traj)
    
    if gui_save or has_clicks or has_keys:
        score += 5
        feedback_parts.append(f"GUI workflow verified (Save detected: {gui_save}, clicks: {click_count})")
    else:
        feedback_parts.append("No GUI interaction detected (possible terminal command usage)")

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }