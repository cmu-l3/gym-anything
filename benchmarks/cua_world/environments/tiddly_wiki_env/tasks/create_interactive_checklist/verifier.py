#!/usr/bin/env python3
"""Verifier for create_interactive_checklist task."""

import json
import tempfile
import os
import re


def _check_trajectory_for_gui_interaction(traj):
    """Analyze agent trajectory for evidence of browser GUI interaction."""
    mouse_clicks = 0
    if not traj:
        return False

    for step in traj:
        action = step.get('action', '') if isinstance(step, dict) else str(step)
        action_lower = action.lower() if isinstance(action, str) else ''
        if any(kw in action_lower for kw in [
            'click', 'mouse_move', 'mouse_click', 'left_click',
            'xdotool click', 'pyautogui.click'
        ]):
            mouse_clicks += 1

    return mouse_clicks > 0


def verify_interactive_checklist(traj, env_info, task_info):
    """Verify that the checklist was built and its checkboxes were clicked."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/checklist_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Checklist Created (10 pts)
    if result.get('checklist_exists'):
        score += 5
        feedback_parts.append("Checklist tiddler exists")
        
        tags = result.get('checklist_tags', '')
        if 'onboarding' in tags.lower():
            score += 5
            feedback_parts.append("Onboarding tag present")
        else:
            feedback_parts.append("FAIL: Onboarding tag missing")
    else:
        feedback_parts.append("FAIL: 'Jane Doe Onboarding' tiddler not found")
        # Can't pass without the core authoring component
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    text = result.get('checklist_text', '')
    text_lower = text.lower()

    # Criterion 2: Checkbox Syntax (20 pts)
    # Check if they used <$checkbox> widgets
    checkbox_count = len(re.findall(r'<\$checkbox', text_lower))
    
    # Also verify they target the tasks (either explicitly with tiddler= or in a <$list>)
    has_list_widget = '<$list' in text_lower
    has_explicit_targets = all(t in text for t in [
        "Task: Order Laptop", 
        "Task: Create Email Account", 
        "Task: Building Access Badge", 
        "Task: Benefits Enrollment"
    ])

    if checkbox_count >= 4 or (checkbox_count >= 1 and has_list_widget):
        score += 20
        feedback_parts.append("Checkbox widgets detected")
    else:
        feedback_parts.append("FAIL: Insufficient <$checkbox> widgets found")

    # Criterion 3: Status Field Binding (20 pts)
    # Should contain field="status" (quotes can be single or double)
    if re.search(r'field=[\'"]status[\'"]', text_lower):
        score += 20
        feedback_parts.append("Field binding 'status' verified")
    else:
        feedback_parts.append("FAIL: field='status' binding missing")

    # Criterion 4: State Values Configured (20 pts)
    has_checked = re.search(r'checked=[\'"]complete[\'"]', text_lower)
    has_unchecked = re.search(r'unchecked=[\'"]pending[\'"]', text_lower)
    
    if has_checked and has_unchecked:
        score += 20
        feedback_parts.append("Checked/Unchecked states configured")
    elif has_checked or has_unchecked:
        score += 10
        feedback_parts.append("Partial state values configured")
    else:
        feedback_parts.append("FAIL: Checked/Unchecked states missing")

    # Criterion 5 & 6: Target State Mutated (15 pts each)
    status_laptop = str(result.get('status_laptop', '')).strip().lower()
    status_email = str(result.get('status_email', '')).strip().lower()
    status_badge = str(result.get('status_badge', '')).strip().lower()
    status_benefits = str(result.get('status_benefits', '')).strip().lower()

    mutations = 0
    if status_laptop == 'complete':
        score += 15
        mutations += 1
        feedback_parts.append("Laptop task marked complete")
    else:
        feedback_parts.append(f"Laptop task status: {status_laptop}")

    if status_email == 'complete':
        score += 15
        mutations += 1
        feedback_parts.append("Email task marked complete")
    else:
        feedback_parts.append(f"Email task status: {status_email}")

    # Check for over-mutation (checking off things they shouldn't have)
    if status_badge == 'complete' or status_benefits == 'complete':
        feedback_parts.append("WARNING: Extra tasks were marked complete incorrectly")
        # Deduct a small amount for lack of precision
        score -= 5

    # Anti-Gaming check: Ensure they didn't just edit the target tiddlers directly
    # We look for server logs showing the GUI dispatched a save task for the target tiddlers
    gui_save = result.get('gui_mutation_detected', False)
    has_clicks = _check_trajectory_for_gui_interaction(traj)
    
    if mutations > 0 and not gui_save and not has_clicks:
        feedback_parts.append("PENALTY: State mutated but no UI interaction detected (direct file edit suspected)")
        # Cap score below passing if they bypassed the UI requirement
        score = min(score, 60)

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }