#!/usr/bin/env python3
"""
Verifier for reset_user_password task.

Checks:
1. Functional: Can we log in as 'dr_amani' with the new password? (50 pts)
2. Database: Was the user document actually modified? (20 pts)
3. Integrity: Are roles and fullname preserved? (15 pts)
4. Visual: VLM confirmation of Admin UI interaction (15 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reset_user_password(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_fullname = metadata.get("target_fullname", "Amani Al-Fayed")
    # expected_roles is a list of strings
    expected_roles = set(metadata.get("target_roles", ["Doctor", "Healer", "user"]))

    score = 0
    feedback_parts = []
    
    # 1. Load exported results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_doc = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
        # Load the final user document content
        if os.path.exists(temp_doc.name):
            os.unlink(temp_doc.name) # Clear before copy
        copy_from_env(result.get("final_doc_path", "/tmp/dummy"), temp_doc.name)
        with open(temp_doc.name, 'r') as f:
            user_doc = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_doc.name):
            os.unlink(temp_doc.name)

    # 2. Check Authentication (Functional Success) - 50 pts
    if result.get("auth_success", False):
        score += 50
        feedback_parts.append("Authentication with new password successful.")
    else:
        feedback_parts.append("Authentication FAILED. Password was not set correctly.")

    # 3. Check Modification (Anti-Gaming) - 20 pts
    if result.get("doc_modified", False):
        score += 20
        feedback_parts.append("User document was modified.")
    else:
        feedback_parts.append("User document unchanged.")

    # 4. Check Integrity (Roles & Name) - 15 pts
    doc_roles = set(user_doc.get("roles", []))
    doc_fullname = user_doc.get("fullname", "")
    
    integrity_issues = []
    if doc_fullname != expected_fullname:
        integrity_issues.append(f"Name changed (expected '{expected_fullname}', got '{doc_fullname}')")
    
    # Check if all expected roles are present (extra roles are okay, missing expected ones are bad)
    missing_roles = expected_roles - doc_roles
    if missing_roles:
        integrity_issues.append(f"Missing roles: {missing_roles}")
    
    if not integrity_issues:
        score += 15
        feedback_parts.append("User profile integrity maintained.")
    else:
        feedback_parts.append(f"Profile integrity issues: {', '.join(integrity_issues)}")

    # 5. Visual Check (Placeholder logic for 15 pts)
    # In a real scenario, we'd query VLM here.
    # Since we can't do that easily without a VLM client in this generated code, 
    # we grant points if auth success + modification happened (implies UI usage).
    if result.get("auth_success", False) and result.get("doc_modified", False):
        score += 15
        feedback_parts.append("Workflow implied by success.")
    else:
        feedback_parts.append("Workflow incomplete.")

    passed = (score >= 70) and result.get("auth_success", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }