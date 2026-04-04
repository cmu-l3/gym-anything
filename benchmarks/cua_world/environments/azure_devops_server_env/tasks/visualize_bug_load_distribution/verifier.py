#!/usr/bin/env python3
"""
Verifier for visualize_bug_load_distribution task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_visualize_bug_load_distribution(traj, env_info, task_info):
    """
    Verify the creation of a bug distribution visualization in Azure DevOps.
    
    Criteria:
    1. Shared Query 'Open Bugs Snapshot' exists (30 pts)
    2. Query logic filters for Bugs and excludes Closed states (20 pts)
    3. Pie Chart widget exists on the Team Dashboard (20 pts)
    4. Widget is configured correctly (Pie, Group By AssignedTo, correct Query) (30 pts)
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Define paths
    remote_path = r"C:\Users\Docker\task_results\visualize_bug_load_distribution_result.json"
    
    # Copy result file
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    
    try:
        copy_from_env(remote_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/parse result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve verification results. Ensure export_result.ps1 ran successfully. Error: {str(e)}"
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # Criterion 1: Query Exists
    if result.get("query_exists") and result.get("query_is_shared"):
        score += 30
        feedback.append("Shared Query 'Open Bugs Snapshot' created successfully.")
    else:
        feedback.append("Failed: Shared Query 'Open Bugs Snapshot' not found or not in Shared Queries.")

    # Criterion 2: Query Logic
    if result.get("query_wiql_correct"):
        score += 20
        feedback.append("Query logic correctly filters for Open Bugs.")
    else:
        if result.get("query_exists"):
            feedback.append("Failed: Query logic is incorrect (Check filters for Work Item Type = Bug and State != Closed).")

    # Criterion 3: Widget Exists
    if result.get("widget_found"):
        score += 20
        feedback.append("Pie Chart widget found on 'TailwindTraders Team' dashboard.")
    else:
        feedback.append("Failed: Pie Chart widget not found on the dashboard.")

    # Criterion 4: Widget Configuration
    if result.get("widget_group_by_correct") and result.get("widget_query_match"):
        score += 30
        feedback.append("Widget configured correctly (Group by 'Assigned To', linked to correct query).")
    else:
        if result.get("widget_found"):
            details = []
            if not result.get("widget_group_by_correct"): details.append("Group By is not 'Assigned To'")
            if not result.get("widget_query_match"): details.append("Widget not linked to the 'Open Bugs Snapshot' query")
            feedback.append(f"Failed: Widget configuration issues: {', '.join(details)}.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }