#!/usr/bin/env python3
"""Verifier for create_project_timeline task."""

import json
import tempfile
import os
import re


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


def verify_create_project_timeline(traj, env_info, task_info):
    """Verify that project timeline and milestones were created correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_milestones = metadata.get('milestones', [
      {"title": "IRB Protocol Submission", "due_date": "20250215", "status": "completed"},
      {"title": "Equipment Procurement", "due_date": "20250301", "status": "completed"},
      {"title": "Participant Recruitment Phase 1", "due_date": "20250430", "status": "in-progress"},
      {"title": "Interim Data Analysis", "due_date": "20250715", "status": "pending"},
      {"title": "Year 1 Progress Report to NIH", "due_date": "20251201", "status": "pending"}
    ])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/project_timeline_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 0: New tiddlers were actually created
    new_count = result.get('current_count', 0) - result.get('initial_count', 0)
    if new_count <= 0:
        feedback_parts.append("FAIL: No new tiddlers created")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Check Milestones (Total 50 pts)
    # Each milestone: exists(3), due_date(3), status(2), tags(2)
    milestones_data = result.get('milestones', {})
    milestones_exist = 0
    dates_correct = 0
    status_correct = 0
    tags_correct = 0

    for i, expected in enumerate(expected_milestones):
        m_key = f"milestone_{i}"
        m_data = milestones_data.get(m_key, {})
        
        if m_data.get('exists'):
            milestones_exist += 1
            score += 3
            
            # Check due date
            actual_date = m_data.get('due_date', '').strip()
            if actual_date == expected['due_date']:
                dates_correct += 1
                score += 3
                
            # Check status
            actual_status = m_data.get('status', '').strip().lower()
            if actual_status == expected['status'].lower():
                status_correct += 1
                score += 2
                
            # Check tags
            actual_tags = m_data.get('tags', '').lower()
            if 'milestone' in actual_tags:
                tags_correct += 1
                score += 2

    feedback_parts.append(f"Milestones: {milestones_exist}/5 exist, {dates_correct}/5 dates correct, {status_correct}/5 status correct, {tags_correct}/5 tags correct")

    # Check Timeline Tiddler (Total 35 pts)
    timeline_content = result.get('timeline_content', '')
    if result.get('timeline_exists'):
        score += 10
        feedback_parts.append("Project Timeline tiddler found")
        
        # Check for $list widget
        if '<$list' in timeline_content or '<$list ' in timeline_content:
            score += 10
            feedback_parts.append("Found <$list> widget")
        else:
            feedback_parts.append("Missing <$list> widget")
            
        # Check for filter operators
        if re.search(r'tag\[Milestone\]', timeline_content, re.IGNORECASE):
            score += 5
            feedback_parts.append("Found tag[Milestone] filter")
        else:
            feedback_parts.append("Missing tag[Milestone] filter")
            
        if re.search(r'sort\[due-date\]', timeline_content, re.IGNORECASE):
            score += 10
            feedback_parts.append("Found sort[due-date] filter")
        else:
            feedback_parts.append("Missing sort[due-date] filter")
    else:
        feedback_parts.append("FAIL: Project Timeline tiddler not found")

    # Anti-gaming: GUI Save Check (15 pts)
    if result.get('gui_save_detected'):
        score += 15
        feedback_parts.append("GUI save detected")
    else:
        feedback_parts.append("No GUI save detected (possible direct file edit)")

    # Provide trajectory analysis insight
    has_clicks, has_keys, click_count = _check_trajectory_for_gui_interaction(traj)
    if has_clicks or has_keys:
        feedback_parts.append(f"Trajectory shows GUI interaction ({click_count} clicks)")
    
    passed = score >= 60 and milestones_exist >= 3 and result.get('timeline_exists')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }