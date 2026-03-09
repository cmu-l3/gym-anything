#!/usr/bin/env python3
"""
Verifier for link_external_file_to_case task.

Verification Strategy:
1. Verify 'Miranda v. Arizona' item exists.
2. Verify it has a child attachment.
3. Verify the attachment's linkMode is 2 (Linked File).
   - linkMode 0 = Imported (Wrong, user copied the file)
   - linkMode 2 = Linked (Correct, user linked to file)
4. Verify the path points to the correct file.

Scoring:
- Attachment created: 30 pts
- Correct Link Mode (Linked, not Stored): 40 pts
- Correct File Path: 30 pts
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_link_external_file_to_case(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/link_external_file_to_case_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve result: {e}"
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Error in export: {result['error']}"}

    score = 0
    feedback = []
    
    miranda_found = result.get("miranda_found", False)
    attachment_found = result.get("attachment_found", False)
    link_mode = result.get("link_mode", -1)
    file_path = result.get("file_path", "")
    
    # 1. Check parent case
    if not miranda_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Critical: 'Miranda v. Arizona' case not found in library."
        }

    # 2. Check attachment existence (30 pts)
    if attachment_found:
        score += 30
        feedback.append("Attachment found on case (+30)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No attachment found on 'Miranda v. Arizona'. Right-click the item -> Add Attachment -> Attach Link to File..."
        }

    # 3. Check Link Mode (40 pts)
    # linkMode 2 is "Linked File". linkMode 0 is "Imported File" (stored copy)
    if link_mode == 2:
        score += 40
        feedback.append("Correctly attached as Linked File (+40)")
    elif link_mode == 0:
        feedback.append("Incorrect attachment type: You attached a Stored Copy (Imported). You must attach a LINK.")
    else:
        feedback.append(f"Incorrect attachment type (Mode: {link_mode})")

    # 4. Check File Path (30 pts)
    # Jurism might store full path or relative path, but it should contain the filename
    expected_filename = "Miranda_Opinion.pdf"
    if expected_filename in file_path:
        score += 30
        feedback.append("Attached correct file (+30)")
    else:
        feedback.append(f"Attached wrong file. Expected '{expected_filename}', got '{file_path}'")

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }