#!/usr/bin/env python3
"""
Verifier for configure_personal_dashboard task.
Validates that the user's My Page has exactly the requested widgets in the correct order.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_personal_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result file
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

    dashboard = result.get("dashboard_state", {})
    task_start = result.get("task_start", 0)

    # Basic checks
    if dashboard.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Internal error checking dashboard: {dashboard['error']}"}
    
    if not dashboard.get("user_found"):
         return {"passed": False, "score": 0, "feedback": "User 'bob.smith' not found in system."}

    if not dashboard.get("grid_exists"):
         return {"passed": False, "score": 0, "feedback": "Dashboard (My Page) has not been initialized/configured."}

    widgets = dashboard.get("widgets", [])
    updated_at = dashboard.get("grid_updated_at", 0)

    score = 0
    feedback = []

    # Criterion 1: Modified during task (Anti-gaming)
    if updated_at > task_start:
        score += 10
        feedback.append("Dashboard was modified during the task.")
    else:
        feedback.append("Dashboard was NOT modified during the task session.")
        # We continue checking, but they likely won't pass fully if they didn't do anything.

    # Identifiers mapping
    # Note: OpenProject widget identifiers can be specific. 
    # 'work_packages_assigned' is standard, but might appear as 'work_packages_table' with options.
    # We look for substrings to be robust across minor OP versions.
    
    wp_widget = None
    time_widget = None
    
    for w in widgets:
        ident = w.get("identifier", "")
        if "work_packages_assigned" in ident:
            wp_widget = w
        elif "work_package" in ident and "assigned" in ident:
            wp_widget = w # Fallback loose match
        
        if "time_entries" in ident or "spent_time" in ident:
            time_widget = w

    # Criterion 2: Correct widgets present
    if wp_widget:
        score += 25
        feedback.append("Found 'Work packages assigned to me' widget.")
    else:
        feedback.append("Missing 'Work packages assigned to me' widget.")

    if time_widget:
        score += 25
        feedback.append("Found 'Spent time' widget.")
    else:
        feedback.append("Missing 'Spent time' widget.")

    # Criterion 3: Clean slate (No extra widgets)
    # The task explicitly asks to remove defaults.
    if len(widgets) == 2:
        if wp_widget and time_widget:
            score += 30
            feedback.append("Dashboard is clean (exactly the 2 requested widgets).")
        else:
            # They have 2 widgets, but not the right ones, so no points for cleanliness yet
            feedback.append(f"Dashboard has 2 widgets, but they are not the correct pair. Found: {[w['identifier'] for w in widgets]}")
    elif len(widgets) > 2:
        feedback.append(f"Dashboard has {len(widgets)} widgets. Default widgets were likely not removed.")
    elif len(widgets) < 2:
        feedback.append("Dashboard has fewer than 2 widgets.")

    # Criterion 4: Order (WP on top)
    if wp_widget and time_widget:
        wp_row = wp_widget.get("start_row", 999)
        time_row = time_widget.get("start_row", 999)
        
        if wp_row < time_row:
            score += 10
            feedback.append("Widget order is correct (Work packages above Spent time).")
        elif wp_row == time_row:
            # Same row? Check column
            wp_col = wp_widget.get("start_column", 999)
            time_col = time_widget.get("start_column", 999)
            if wp_col < time_col:
                score += 10
                feedback.append("Widget order is correct (Work packages to the left of Spent time).")
            else:
                feedback.append("Widget order incorrect (Work packages should be first).")
        else:
            feedback.append("Widget order incorrect (Work packages should be above/before Spent time).")

    return {
        "passed": score >= 90,
        "score": score,
        "feedback": " ".join(feedback)
    }