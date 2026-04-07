#!/usr/bin/env python3
"""
Verifier for restructure_project_hierarchy task.

Checks:
1. "Chassis Design", "Power Systems", and "Navigation Software" are subprojects of "Mars Rover 2030".
2. Project IDs match the initial state (projects were moved, not deleted/recreated).
3. "Mars Rover 2030" is still a top-level project.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restructure_project_hierarchy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    final_state = result.get("final_state", {})
    initial_state = result.get("initial_state", {})

    mars_proj = final_state.get("mars_rover", {})
    chassis_proj = final_state.get("chassis", {})
    power_proj = final_state.get("power", {})
    nav_proj = final_state.get("navigation", {})

    # Retrieve IDs
    mars_id = mars_proj.get("id")
    chassis_id = chassis_proj.get("id")
    power_id = power_proj.get("id")
    nav_id = nav_proj.get("id")

    # Retrieve Parent info (API returns a dict {id: X, name: Y} for parent)
    chassis_parent = chassis_proj.get("parent", {})
    power_parent = power_proj.get("parent", {})
    nav_parent = nav_proj.get("parent", {})
    mars_parent = mars_proj.get("parent", {}) # Should be None/Empty

    score = 0
    feedback = []

    # 1. Verify Target Parent Integrity (10 pts)
    # Mars Rover should exist and NOT have a parent (or parent is null)
    if mars_id and not mars_parent:
        score += 10
        feedback.append("Mars Rover project is top-level.")
    else:
        feedback.append("Mars Rover project is missing or nested incorrectly.")

    # 2. Verify Project Preservation (15 pts)
    # IDs must match initial state
    ids_preserved = (
        chassis_id == initial_state.get("chassis") and
        power_id == initial_state.get("power") and
        nav_id == initial_state.get("navigation") and
        mars_id == initial_state.get("mars_rover")
    )
    if ids_preserved:
        score += 15
        feedback.append("Project IDs preserved (moved correctly).")
    else:
        feedback.append("Project IDs changed (projects likely re-created).")

    # 3. Verify Nesting (25 pts each)
    def verify_child(name, child_parent_data, target_parent_id):
        if child_parent_data and child_parent_data.get("id") == target_parent_id:
            return 25, f"{name} nested correctly."
        return 0, f"{name} NOT nested correctly."

    s_chassis, f_chassis = verify_child("Chassis", chassis_parent, mars_id)
    s_power, f_power = verify_child("Power", power_parent, mars_id)
    s_nav, f_nav = verify_child("Navigation", nav_parent, mars_id)

    score += s_chassis
    score += s_power
    score += s_nav
    
    feedback.append(f_chassis)
    feedback.append(f_power)
    feedback.append(f_nav)

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " ".join(feedback)
    }