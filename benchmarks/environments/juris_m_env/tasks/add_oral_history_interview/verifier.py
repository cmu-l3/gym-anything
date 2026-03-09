#!/usr/bin/env python3
"""
Verifier for add_oral_history_interview task.

Criteria:
1. Item exists with correct title.
2. Item type is 'interview'.
3. Metadata checks: Date, URL, Medium.
4. Creator roles: 
   - John Lewis MUST be 'interviewee'
   - Julian Bond MUST be 'interviewer'
   
Anti-gaming:
- Item must be created during task (checked via export logic finding item after cleanup).
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_oral_history_interview(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result JSON
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/add_oral_history_interview_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load result JSON: {e}"
        }

    score = 0
    feedback_parts = []
    
    # 1. Check Item Existence (20 pts)
    if not result.get("item_found", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No item found with title 'Oral history interview with John Lewis'. Did you create the item?",
            "details": result
        }
    score += 20
    feedback_parts.append("Item created (+20)")

    item_data = result.get("item", {})
    creators = result.get("creators", [])

    # 2. Check Item Type (10 pts)
    # Jurism internal type name for Interview is usually "interview"
    actual_type = item_data.get("type", "").lower()
    if actual_type == "interview":
        score += 10
        feedback_parts.append("Item type is Interview (+10)")
    else:
        feedback_parts.append(f"Incorrect item type: {actual_type} (expected 'interview')")

    # 3. Check Metadata (20 pts)
    # Date
    date = item_data.get("date", "")
    if "2013" in date:
        score += 7
    else:
        feedback_parts.append(f"Date mismatch: '{date}' (expected 2013)")
        
    # URL
    url = item_data.get("url", "")
    if "loc.gov" in url:
        score += 7
    else:
        feedback_parts.append("URL missing or incorrect")
        
    # Medium
    medium = item_data.get("medium", "").lower()
    if "transcript" in medium:
        score += 6
    else:
        feedback_parts.append(f"Medium mismatch: '{medium}' (expected Transcript)")

    # 4. Check Creator Roles (40 pts) - CRITICAL
    # We need:
    # - Lewis -> Interviewee
    # - Bond -> Interviewer
    
    lewis_found = False
    lewis_correct = False
    bond_found = False
    bond_correct = False
    
    for c in creators:
        name = c.get("full_name", "")
        role = c.get("role", "").lower()
        
        if "Lewis" in name:
            lewis_found = True
            # In Zotero/Jurism, the default role for Interview type is 'interviewee' or 'contributor' depending on version.
            # But specific role 'interviewee' is expected here.
            if role == "interviewee":
                lewis_correct = True
        
        if "Bond" in name:
            bond_found = True
            if role == "interviewer":
                bond_correct = True
    
    # Scoring Creators
    if lewis_found:
        if lewis_correct:
            score += 20
            feedback_parts.append("John Lewis correctly set as Interviewee (+20)")
        else:
            score += 5
            feedback_parts.append("John Lewis found but wrong role (expected Interviewee) (+5)")
    else:
        feedback_parts.append("John Lewis not listed as creator")

    if bond_found:
        if bond_correct:
            score += 20
            feedback_parts.append("Julian Bond correctly set as Interviewer (+20)")
        else:
            score += 5
            feedback_parts.append("Julian Bond found but wrong role (expected Interviewer) (+5)")
    else:
        feedback_parts.append("Julian Bond not listed as creator")

    # 5. Anti-gaming (10 pts)
    if result.get("created_during_task", False):
        score += 10
        feedback_parts.append("Item created during task session (+10)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }