#!/usr/bin/env python3
"""
Verifier for secure_folder_custom_acl task.
Verifies the agent correctly configured folder security and content in Nuxeo.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_folder_custom_acl(traj, env_info, task_info):
    """
    Verify the Nuxeo security task.
    
    Expected outcomes:
    1. Folder 'Confidential HR Documents' exists in Projects
    2. Inheritance is blocked
    3. User 'jsmith' has ReadWrite
    4. Group 'members' has Read
    5. Note document exists inside
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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
    max_score = 100
    feedback_parts = []
    
    # ---------------------------------------------------
    # Criterion 1: Folder Creation (20 pts)
    # ---------------------------------------------------
    if result.get("folder_found"):
        title = result.get("folder_metadata", {}).get("title", "")
        doc_type = result.get("folder_metadata", {}).get("type", "")
        
        if doc_type == "Folder":
            if "Confidential" in title:
                score += 20
                feedback_parts.append("Folder created correctly")
            else:
                score += 15
                feedback_parts.append(f"Folder created but title mismatch ('{title}')")
        else:
            score += 10
            feedback_parts.append(f"Document created but wrong type ({doc_type})")
    else:
        return {"passed": False, "score": 0, "feedback": "Confidential folder not found inside Projects workspace"}

    # ---------------------------------------------------
    # Criterion 2: Inheritance Blocked (25 pts)
    # ---------------------------------------------------
    if result.get("inheritance_blocked"):
        score += 25
        feedback_parts.append("Inheritance blocked")
    else:
        feedback_parts.append("Inheritance NOT blocked")

    # ---------------------------------------------------
    # Criterion 3: jsmith Permissions (20 pts)
    # ---------------------------------------------------
    jsmith_perm = result.get("jsmith_permission")
    if jsmith_perm in ["ReadWrite", "Everything", "Read & Write"]:
        score += 20
        feedback_parts.append("jsmith has ReadWrite")
    elif jsmith_perm == "Read":
        score += 10
        feedback_parts.append("jsmith has Read (expected ReadWrite)")
    elif jsmith_perm:
        score += 5
        feedback_parts.append(f"jsmith has incorrect permission ({jsmith_perm})")
    else:
        feedback_parts.append("jsmith has no explicit permission")

    # ---------------------------------------------------
    # Criterion 4: members Permissions (15 pts)
    # ---------------------------------------------------
    members_perm = result.get("members_permission")
    if members_perm == "Read":
        score += 15
        feedback_parts.append("members group has Read")
    elif members_perm in ["ReadWrite", "Everything"]:
        score += 8
        feedback_parts.append("members group has too much access (ReadWrite)")
    elif members_perm:
        score += 5
        feedback_parts.append(f"members group has incorrect permission ({members_perm})")
    else:
        feedback_parts.append("members group has no explicit permission")

    # ---------------------------------------------------
    # Criterion 5: Note Document (20 pts)
    # ---------------------------------------------------
    if result.get("note_found"):
        score += 20
        feedback_parts.append("Note document created")
    else:
        # Check if any child exists
        children = result.get("children", [])
        if children:
            score += 10
            feedback_parts.append("Child document created but title/type incorrect")
        else:
            feedback_parts.append("No document created inside folder")

    # ---------------------------------------------------
    # Final Evaluation
    # ---------------------------------------------------
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }