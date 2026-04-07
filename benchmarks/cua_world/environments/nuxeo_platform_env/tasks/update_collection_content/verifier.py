#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_collection_content(traj, env_info, task_info):
    """
    Verify the update_collection_content task.
    
    Expected State:
    1. 'Brand Assets' collection description updated.
    2. 'Obsolete-Logo' removed.
    3. 'Logo-2024' added.
    4. 'Campaign-Overview' added.
    """
    
    # 1. Copy result file from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check basics
    if not result.get("collection_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Collection 'Brand Assets' not found. Error: {result.get('error')}"
        }

    score = 0
    feedback = []
    
    # 3. Check Description (20 pts)
    # Expected: "Approved brand assets for 2024 campaigns"
    # Allow some flexibility in whitespace/case
    actual_desc = result.get("description", "").strip()
    expected_desc = "Approved brand assets for 2024 campaigns"
    
    if expected_desc.lower() in actual_desc.lower():
        score += 20
        feedback.append("Description updated correctly.")
    else:
        feedback.append(f"Description mismatch. Expected '{expected_desc}', got '{actual_desc}'.")

    # 4. Check Content (60 pts)
    members = result.get("members", [])
    
    # Check Removals (20 pts)
    if "Obsolete-Logo" not in members:
        score += 20
        feedback.append("Obsolete item removed.")
    else:
        feedback.append("Obsolete item still present.")
        
    # Check Additions (20 pts each)
    if "Logo-2024" in members:
        score += 20
        feedback.append("Logo-2024 added.")
    else:
        feedback.append("Logo-2024 not found in collection.")
        
    if "Campaign-Overview" in members:
        score += 20
        feedback.append("Campaign-Overview added.")
    else:
        feedback.append("Campaign-Overview not found in collection.")

    # 5. App Running Check (20 pts)
    # Simple check that they didn't just close the app
    if result.get("app_running", False):
        score += 20
        feedback.append("Application left running.")
    else:
        feedback.append("Application was closed.")

    # Final scoring
    passed = score >= 80  # Requires most steps to be correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }