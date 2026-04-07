#!/usr/bin/env python3
"""
Verifier for build_interactive_inventory_dashboard task.

Verifies the creation of a dynamic dashboard utilizing TiddlyWiki action widgets
and mathematical filter operators to mutate the state of multiple other tiddlers.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_trajectory_for_gui_interaction(traj):
    """Analyze agent trajectory for evidence of browser GUI interaction."""
    mouse_clicks = 0
    if not traj:
        return False

    for step in traj:
        action = step.get('action', '') if isinstance(step, dict) else str(step)
        action_lower = action.lower() if isinstance(action, str) else ''
        if any(kw in action_lower for kw in [
            'click', 'mouse_move', 'mouse_click', 'left_click', 'double_click', 
            'xdotool mousemove', 'pyautogui.click'
        ]):
            mouse_clicks += 1

    return mouse_clicks > 0


def verify_inventory_dashboard(traj, env_info, task_info):
    """
    Verify the Reagent Inventory dashboard logic via static analysis of the Wikitext.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract JSON export from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/inventory_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Validation flags
    dashboard_exists = result.get("dashboard_exists", False)
    dashboard_text = result.get("dashboard_text", "")
    reagents_intact = result.get("reagents_intact", False)
    gui_save = result.get("gui_save_detected", False)
    
    # 1. Existence of the Dashboard (20 pts)
    if dashboard_exists:
        score += 20
        feedback_parts.append("Dashboard tiddler exists")
        
        # Anti-gaming: Ensure it was created after the task started
        mtime = result.get("dashboard_mtime", 0)
        start_time = result.get("task_start_time", 0)
        if start_time > 0 and mtime < start_time:
            feedback_parts.append("WARNING: Dashboard file predates task start time")
            score -= 20
    else:
        feedback_parts.append("FAIL: Dashboard tiddler 'Reagent Inventory' not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Reagents Integrity (10 pts)
    # Ensure the agent didn't delete the target data to bypass listing logic
    if reagents_intact:
        score += 10
        feedback_parts.append("Original reagents intact")
    else:
        feedback_parts.append("FAIL: Original reagent tiddlers were deleted or corrupted")

    # Lowercase text for easier heuristic matching, but keep original for strict widget checks
    text_lower = dashboard_text.lower()

    # 3. Dynamic List Widget (15 pts)
    # Looking for: <$list filter="...tag[Reagent]...">
    if "<$list" in dashboard_text and ("tag[Reagent]" in dashboard_text or "tag[reagent]" in text_lower):
        score += 15
        feedback_parts.append("Dynamic list widget used")
    else:
        feedback_parts.append("FAIL: No `<$list>` widget targeting the `Reagent` tag found")

    # 4. Field Displays (15 pts)
    # Looking for transclusion of stock_level and unit: {{!!stock_level}}, <$view field="stock_level"/>, etc.
    if "stock_level" in dashboard_text and "unit" in dashboard_text:
        score += 15
        feedback_parts.append("Data fields referenced")
    else:
        feedback_parts.append("FAIL: Missing references to `stock_level` and/or `unit` fields")

    # 5. Interactive Action Widgets (20 pts)
    has_button = "<$button" in dashboard_text
    has_action = "<$action-setfield" in dashboard_text
    if has_button and has_action and "stock_level" in dashboard_text:
        score += 20
        feedback_parts.append("Action widgets configured")
    elif has_button or has_action:
        score += 10
        feedback_parts.append("Partial action widgets configured")
    else:
        feedback_parts.append("FAIL: Missing required interactive widgets (`<$button>`, `<$action-setfield>`)")

    # 6. Mathematical Filter Logic (20 pts)
    # We need to see addition and subtraction logic linked to the stock level.
    # Typically looks like: $value={{{ [{!!stock_level}add[1]] }}} or <$filter...add[1]>
    has_add = "add[1]" in text_lower
    has_sub = "subtract[1]" in text_lower
    
    if has_add and has_sub:
        score += 20
        feedback_parts.append("Mathematical logic (add/subtract) applied")
    elif has_add or has_sub:
        score += 10
        feedback_parts.append("Partial mathematical logic applied")
    else:
        feedback_parts.append("FAIL: Missing `add[1]` and `subtract[1]` filter operations")

    # 7. GUI Usage Verification (Anti-gaming check)
    has_gui_clicks = _check_trajectory_for_gui_interaction(traj)
    if not has_gui_clicks and not gui_save:
        feedback_parts.append("WARNING: No GUI interactions detected. Possible CLI bypass.")
        # We don't necessarily fail them strictly for this if the code is perfect, 
        # but it serves as a strong signal. If the score is high, let it pass.
    
    passed = score >= 80 and dashboard_exists and has_action and (has_add or has_sub)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }