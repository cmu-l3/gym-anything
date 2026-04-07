#!/usr/bin/env python3
"""Verifier for build_master_detail_explorer task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_master_detail_explorer(traj, env_info, task_info):
    """
    Verify that the Master-Detail Medication Explorer was built correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve output from the container
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
    feedback_parts = []
    
    # 1. Tiddler Creation & Tags (10 points)
    if result.get("tiddler_exists"):
        if result.get("has_dashboard_tag"):
            score += 10
            feedback_parts.append("Tiddler exists and tagged 'Dashboard'")
        else:
            score += 5
            feedback_parts.append("Tiddler exists but missing 'Dashboard' tag")
    else:
        feedback_parts.append("FAIL: 'Medication Explorer' tiddler not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # 2. Split-Pane Layout (15 points)
    if result.get("has_flex_layout"):
        score += 15
        feedback_parts.append("Split-pane structural CSS/HTML detected")
    else:
        feedback_parts.append("No layout CSS (flex/grid/width) detected")

    # 3. Dynamic Master List (15 points)
    if result.get("has_list_widget"):
        score += 15
        feedback_parts.append("List widget querying [tag[Medication]] found")
    else:
        feedback_parts.append("FAIL: No appropriate <$list> widget found")

    # 4. Interactive State Buttons (25 points)
    has_state_interaction = False
    if result.get("has_state_button"):
        score += 25
        has_state_interaction = True
        feedback_parts.append("State-mutating buttons detected")
    else:
        feedback_parts.append("FAIL: No state mutation (<$button set=... or <$action-setfield>) detected")

    # 5. Detail Pane Field Rendering & Dynamic Transclusion (25 points)
    field_score = 0
    fields_found = 0
    if result.get("has_class_field"): fields_found += 1
    if result.get("has_ind_field"): fields_found += 1
    if result.get("has_se_field"): fields_found += 1
    
    has_detail_pane = False
    if result.get("has_dynamic_context"):
        has_detail_pane = True
        if fields_found == 3:
            field_score = 25
            feedback_parts.append("Dynamic context and all required fields transcluded")
        else:
            field_score = 15
            feedback_parts.append(f"Dynamic context found, but only {fields_found}/3 fields explicitly transcluded")
    else:
        if fields_found > 0:
            field_score = 10
            feedback_parts.append(f"Fields transcluded ({fields_found}/3), but dynamic state context missing")
        else:
            feedback_parts.append("FAIL: Dynamic state context and fields missing")
            
    score += field_score

    # 6. Empty State Handling (10 points)
    if result.get("has_empty_state"):
        score += 10
        feedback_parts.append("Empty state text detected")
    else:
        feedback_parts.append("Empty state 'Please select a medication.' text missing")

    # Anti-gaming: Check if save was mediated by TiddlyWiki GUI
    if not result.get("gui_save_detected"):
        feedback_parts.append("WARNING: No GUI save detected; possible direct file manipulation.")

    # Pass condition: must have core interactivity (List + State Buttons + Detail Pane) and score >= 75
    core_interaction_met = result.get("has_list_widget") and has_state_interaction and has_detail_pane
    passed = (score >= 75) and core_interaction_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }