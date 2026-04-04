#!/usr/bin/env python3
"""
Verifier for externalize_strings_i18n@1 task.
"""

import json
import tempfile
import os
import logging
import sys

# Add parent dir to path to import utils if needed
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

logger = logging.getLogger(__name__)

def verify_externalize_strings(traj, env_info, task_info):
    """
    Verify that strings were externalized correctly.
    
    Criteria:
    1. messages.properties created with sufficient entries (> 10) (25 pts)
    2. Messages.java accessor class created (15 pts)
    3. LibraryApp.java modified to use Messages.getString() (25 pts)
    4. Project compiles successfully (15 pts)
    5. Anti-gaming: File was modified & created during task time (10 pts)
    6. VLM: Visual confirmation of wizard usage (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Import VLM utils if available
    vlm_result = {}
    try:
        from utils.eclipse_verification_utils import vlm_verify_eclipse_task
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Use Eclipse Externalize Strings wizard to extract strings to messages.properties",
            checklist_items=[
                "Externalize Strings wizard dialog shown",
                "User selecting strings in the wizard",
                "Source code updated with Messages.getString calls"
            ]
        ) or {}
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    # Load result JSON
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Properties File (25 pts)
    props_exists = result.get("properties_file_exists", False)
    props_count = result.get("properties_entry_count", 0)
    
    if props_exists:
        if props_count >= 15:
            score += 25
            feedback.append(f"messages.properties exists with {props_count} entries (Excellent)")
        elif props_count >= 5:
            score += 15
            feedback.append(f"messages.properties exists with {props_count} entries (Good)")
        else:
            score += 5
            feedback.append(f"messages.properties exists but only has {props_count} entries (Too few)")
    else:
        feedback.append("messages.properties NOT found")

    # 2. Accessor Class (15 pts)
    if result.get("accessor_file_exists", False):
        score += 15
        feedback.append("Messages.java accessor class created")
        
        # Check content sanity
        content = result.get("accessor_content", "")
        if "getString" in content and "ResourceBundle" in content:
            feedback.append("Messages.java content looks valid")
        else:
            score -= 5
            feedback.append("Messages.java content looks suspicious")
    else:
        feedback.append("Messages.java NOT found")

    # 3. Code Modification (25 pts)
    file_modified = result.get("file_modified", False)
    get_string_count = result.get("get_string_count", 0)
    
    if file_modified and get_string_count > 0:
        if get_string_count >= 10:
            score += 25
            feedback.append(f"LibraryApp.java updated with {get_string_count} usage(s) of Messages.getString")
        else:
            score += 15
            feedback.append(f"LibraryApp.java updated partially ({get_string_count} usages)")
    elif not file_modified:
        feedback.append("LibraryApp.java was NOT modified")
    else:
        feedback.append("LibraryApp.java modified but no Messages.getString calls found")

    # 4. Compilation (15 pts)
    if result.get("build_success", False):
        score += 15
        feedback.append("Project compiles successfully")
    else:
        feedback.append("Project build FAILED")

    # 5. Anti-gaming / Timestamp (10 pts)
    task_start = result.get("task_start_time", 0)
    props_mtime = result.get("properties_mtime", 0)
    
    if props_exists and props_mtime > task_start:
        score += 10
        feedback.append("Properties file created during task session")
    elif props_exists:
        feedback.append("Properties file timestamp is invalid/old")

    # 6. VLM Verification (10 pts)
    vlm_score = vlm_result.get("vlm_score", 0)
    if vlm_result.get("vlm_passed"):
        score += 10
        feedback.append("VLM: Visual verification passed")
    elif vlm_score > 0:
        score += 5
        feedback.append(f"VLM: Partial visual verification ({vlm_score})")
    
    # Cap score at 100
    score = min(100, score)
    passed = score >= 60 and props_exists and result.get("build_success", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }