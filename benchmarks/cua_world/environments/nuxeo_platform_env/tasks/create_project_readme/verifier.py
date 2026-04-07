#!/usr/bin/env python3
"""
Verifier for create_project_readme task.

Verifies:
1. A Note document exists (20 pts)
2. The title is "Project Readme" (10 pts)
3. The content contains a valid internal link to "Annual Report 2023" (35 pts)
4. The content contains a valid internal link to "Project Proposal" (35 pts)

Uses copy_from_env to read the JSON result exported from the container.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_project_readme(traj, env_info, task_info):
    """
    Verify the creation of the Project Readme note with internal links.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    
    # 1. Check Note Existence
    note_exists = result.get("note_exists", False)
    if not note_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No Note document named 'Project Readme' was found."
        }
    
    score += 20
    feedback_parts.append("Note document created")
    
    # 2. Check Title
    title = result.get("note_title", "")
    if "Project Readme" in title:
        score += 10
        feedback_parts.append("Title correct")
    else:
        feedback_parts.append(f"Title incorrect ('{title}')")
        
    # 3. Check Links
    # In Nuxeo, internal links in the Note editor are stored as references to the UUID.
    # Examples: <a href=".../resolve/UID"> or data-link-uid="UID"
    # We simply check if the target UUID appears in the HTML content string.
    
    content = result.get("note_content", "")
    targets = result.get("target_uids", {})
    
    uid_report = targets.get("annual_report", "")
    uid_proposal = targets.get("project_proposal", "")
    
    # Verify Annual Report Link
    if uid_report and uid_report in content:
        score += 35
        feedback_parts.append("Annual Report linked")
    elif uid_report:
        feedback_parts.append("Annual Report link MISSING")
    else:
        feedback_parts.append("Target 'Annual Report' not found in system (setup error?)")
        
    # Verify Project Proposal Link
    if uid_proposal and uid_proposal in content:
        score += 35
        feedback_parts.append("Project Proposal linked")
    elif uid_proposal:
        feedback_parts.append("Project Proposal link MISSING")
    else:
        feedback_parts.append("Target 'Project Proposal' not found in system (setup error?)")
        
    # Final Evaluation
    passed = score >= 90  # Requires existence (20) + title (10) + both links (70) = 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }