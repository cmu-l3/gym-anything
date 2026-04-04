#!/usr/bin/env python3
"""
Verifier for create_delivery_plan task.
Verifies that a Delivery Plan was created with specific team, backlog, field, and marker configurations.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_create_delivery_plan(traj, env_info, task_info):
    """
    Verify the Delivery Plan configuration.
    
    Criteria:
    1. Plan "Q1 Roadmap" exists (30 pts)
    2. Configured for 'TailwindTraders Team' and 'Stories' backlog (20 pts)
    3. Card fields include 'Priority' (25 pts)
    4. Marker 'Beta Launch' exists at correct date (25 pts)
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Define paths
    # Windows path in the VM, verified from previous examples
    win_result_path = r"C:\Users\Docker\task_results\create_delivery_plan_result.json"
    
    # Copy result file to temp
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    
    try:
        copy_from_env(win_result_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve task results. Did the export script run? Error: {e}"
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    
    # 1. Verify Plan Existence
    if not result.get("plan_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Delivery Plan 'Q1 Roadmap' was not found in the project."
        }
    
    score += 30
    feedback.append("Plan 'Q1 Roadmap' created.")
    
    # 2. Verify Team and Backlog Configuration
    # structure: team_config is a list of dicts, e.g. [{'id': '...', 'name': 'TailwindTraders Team', 'backlogCategory': 'Microsoft.RequirementCategory'}]
    # Note: 'Stories' usually maps to 'Microsoft.RequirementCategory' in Agile process
    team_config = result.get("team_config", [])
    team_correct = False
    backlog_correct = False
    
    for team in team_config:
        # Check Name (loose match to allow for GUIDs if name not present, but name usually is)
        if "TailwindTraders Team" in str(team.get("name", "")) or "TailwindTraders Team" in str(team.get("team", {}).get("name", "")):
            team_correct = True
        
        # Check Backlog
        # Common categories: Microsoft.RequirementCategory (Stories), Microsoft.BugCategory (Bugs)
        cat = team.get("backlogCategory", "")
        if "RequirementCategory" in cat or "Stories" in cat:
            backlog_correct = True
            
    if team_correct and backlog_correct:
        score += 20
        feedback.append("Correct Team and Backlog configured.")
    elif team_correct:
        score += 10
        feedback.append("Correct Team configured, but wrong Backlog level (expected Stories).")
    elif backlog_correct:
        score += 10
        feedback.append("Correct Backlog level, but wrong Team.")
    else:
        feedback.append("Incorrect Team and Backlog configuration.")

    # 3. Verify Card Fields ('Priority')
    # Settings structure can be deep. Flatten or search recursively.
    # settings -> cardSettings -> fields -> [{'fieldIdentifier': 'Microsoft.VSTS.Common.Priority'}]
    settings = result.get("settings", {})
    card_settings = settings.get("cardSettings", [])
    if isinstance(card_settings, dict):
        card_settings = [card_settings] # Normalize to list
        
    priority_found = False
    
    # Search in card settings
    # Sometimes it's a list of objects per backlog
    for setting in card_settings:
        fields = setting.get("fields", [])
        for f in fields:
            fid = f.get("fieldIdentifier", "") if isinstance(f, dict) else str(f)
            if "Priority" in fid:
                priority_found = True
                break
    
    if priority_found:
        score += 25
        feedback.append("Priority field added to cards.")
    else:
        feedback.append("Priority field NOT found in card settings.")

    # 4. Verify Markers
    # Markers is a list: [{'date': '2026-03-20T00:00:00Z', 'label': 'Beta Launch'}]
    markers = result.get("markers", [])
    marker_found = False
    
    expected_date_sub = "2026-03-20"
    
    for m in markers:
        m_label = m.get("label", "")
        m_date = m.get("date", "")
        if "Beta Launch" in m_label and expected_date_sub in m_date:
            marker_found = True
            break
            
    if marker_found:
        score += 25
        feedback.append("Timeline marker 'Beta Launch' created correctly.")
    else:
        # Partial credit check
        label_match = any("Beta Launch" in m.get("label", "") for m in markers)
        date_match = any(expected_date_sub in m.get("date", "") for m in markers)
        
        if label_match and date_match:
            # Maybe different markers?
            score += 10
            feedback.append("Marker components found but not combined correctly.")
        elif label_match:
            score += 10
            feedback.append("Marker label found but date was incorrect.")
        elif date_match:
            score += 5
            feedback.append("Marker date found but label was incorrect.")
        else:
            feedback.append("No matching timeline marker found.")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " ".join(feedback)
    }