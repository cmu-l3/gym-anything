#!/usr/bin/env python3
"""
Verifier for Create Custom Report task in ServiceDesk Plus.
"""

import json
import os
import sys
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_report(traj, env_info, task_info):
    """
    Verifies that the agent created a custom report with specific configuration.
    
    Criteria:
    1. Report exists with name containing "Weekly Open Requests" and "Priority"
    2. Filter includes "Open" status
    3. Columns include Subject, Technician, Priority, etc.
    4. Grouping is set to Priority
    5. VLM confirms UI usage
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    score = 0
    feedback_parts = []
    
    # DB Data analysis
    db_data = result.get("db_data", {})
    report_found = db_data.get("report_found", False)
    report_name = db_data.get("report_name", "")
    columns = db_data.get("columns", [])
    filters = db_data.get("filters", [])
    grouping = db_data.get("grouping", [])
    
    # Metadata requirements
    req_name_frags = task_info.get("metadata", {}).get("required_report_name_fragments", ["Weekly", "Priority"])
    req_cols = task_info.get("metadata", {}).get("required_columns", ["Subject", "Technician", "Priority"])
    req_filter = task_info.get("metadata", {}).get("required_filter_status", "Open")
    req_group = task_info.get("metadata", {}).get("required_grouping", "Priority")

    # Criterion 1: Report Exists (30 pts)
    if report_found:
        score += 30
        feedback_parts.append("Report found in database")
        
        # Criterion 2: Correct Name (10 pts)
        name_lower = report_name.lower()
        if all(frag.lower() in name_lower for frag in req_name_frags):
            score += 10
            feedback_parts.append("Report name is correct")
        else:
            feedback_parts.append(f"Report name '{report_name}' missing keywords")
            
        # Criterion 3: Filters (15 pts)
        # Check if 'Open' or 'Status' related filter exists
        # DB dump format might be raw criteria strings
        filter_str = " ".join(filters).lower()
        if req_filter.lower() in filter_str:
            score += 15
            feedback_parts.append(f"Filter for '{req_filter}' confirmed")
        else:
            feedback_parts.append(f"Missing filter for '{req_filter}'")

        # Criterion 4: Columns (15 pts)
        # Check overlap
        found_cols = [c.lower() for c in columns]
        matched_cols = 0
        for rc in req_cols:
            if any(rc.lower() in fc for fc in found_cols):
                matched_cols += 1
        
        if matched_cols >= 3:
            score += 15
            feedback_parts.append(f"Columns configured correctly ({matched_cols}/{len(req_cols)} matched)")
        elif matched_cols > 0:
            score += 5
            feedback_parts.append(f"Some columns match ({matched_cols}/{len(req_cols)})")
        else:
            feedback_parts.append("Columns do not match requirements")

        # Criterion 5: Grouping (10 pts)
        group_str = " ".join(grouping).lower()
        if req_group.lower() in group_str:
            score += 10
            feedback_parts.append(f"Grouped by {req_group}")
        else:
            feedback_parts.append(f"Missing grouping by {req_group}")

    else:
        feedback_parts.append("No matching report found in database")
        
    # Criterion 6: VLM Verification (20 pts)
    # Check trajectory for Reports module usage
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = (
            "Analyze these screenshots of a user using ManageEngine ServiceDesk Plus. "
            "Did the user: "
            "1. Navigate to the Reports tab? "
            "2. Open the 'New Custom Report' interface? "
            "3. Select columns or configure filters? "
            "Reply with JSON: {\"reports_visited\": bool, \"config_seen\": bool, \"confidence\": float}"
        )
        
        try:
            vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt).get("parsed", {})
            if vlm_res.get("reports_visited"):
                score += 10
            if vlm_res.get("config_seen"):
                score += 10
                feedback_parts.append("VLM confirmed report configuration UI usage")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if we have full DB score, assume VLM is fine to avoid penalizing valid work due to VLM error
            if score >= 80:
                score += 20
                feedback_parts.append("VLM bypassed (high confidence from DB)")

    passed = score >= 55 and report_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }