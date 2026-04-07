#!/usr/bin/env python3
"""
Verifier for customize_project_overview task.
Checks if the agent successfully customized the project dashboard to include specific widgets.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_project_overview(traj, env_info, task_info):
    """
    Verify that the 'Mobile Banking App' project overview has been customized
    to include 'members' and 'news' widgets.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected widgets from metadata (default to members and news)
    metadata = task_info.get('metadata', {})
    required_widgets = set(metadata.get('required_widgets', ['members', 'news']))

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Parse Rails output
    rails_data = result_data.get('rails_output', {})
    if not rails_data:
        return {"passed": False, "score": 0, "feedback": "No data returned from OpenProject database check."}
    
    if rails_data.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Internal verification error: {rails_data['error']}"}

    project_found = rails_data.get('project_found', False)
    custom_grid_exists = rails_data.get('custom_grid_exists', False)
    actual_widgets = set(rails_data.get('widgets', []))

    feedback_lines = []
    score = 0

    # Criterion 1: Custom Grid Exists (40 pts)
    # The default view does NOT create a Grids::Overview record in the DB until customized.
    if custom_grid_exists:
        score += 40
        feedback_lines.append("Success: Custom dashboard configuration saved.")
    else:
        feedback_lines.append("Fail: No custom dashboard configuration found. Did you click 'Save'?")
        return {
            "passed": False,
            "score": 0,
            "feedback": "\n".join(feedback_lines)
        }

    # Criterion 2: Check for required widgets (30 pts per widget)
    # We normalized widget identifiers to match OpenProject's internal names
    # 'members' -> 'members'
    # 'news' -> 'news'
    
    missing_widgets = []
    for w in required_widgets:
        if w in actual_widgets:
            score += 30
            feedback_lines.append(f"Success: Widget '{w}' is present.")
        else:
            missing_widgets.append(w)
            feedback_lines.append(f"Fail: Widget '{w}' is missing from the dashboard.")

    passed = (len(missing_widgets) == 0) and custom_grid_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }