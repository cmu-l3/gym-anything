#!/usr/bin/env python3
"""
Verifier for version_control_document task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_version_control_document(traj, env_info, task_info):
    """
    Verifies that the document was updated using version control.
    
    Criteria:
    1. Document exists in the case (20 pts).
    2. Version label is > 1.0 (implies update/versioning used) (30 pts).
    3. Content matches the final approved text (30 pts).
    4. Only one file with similar name exists (no duplicates) (20 pts).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    
    doc_info = result.get('doc_info', {})
    found = doc_info.get('found', False)
    version_label = doc_info.get('versionLabel', '1.0')
    count = doc_info.get('count', 0)
    content_match = result.get('content_match', False)
    content_is_draft = result.get('content_is_draft', False)

    # Criterion 1: Document Found
    if found:
        score += 20
        feedback_parts.append("Document found")
    else:
        return {"passed": False, "score": 0, "feedback": "Document 'Investigation_Plan.txt' not found in case"}

    # Criterion 2: Version Increment
    # We expect version to be something like "1.1", "2.0", etc.
    # If it is "1.0", the agent didn't update it or deleted/reuploaded (resetting version usually, or simple upload)
    try:
        ver_float = float(version_label)
        if ver_float > 1.0:
            score += 30
            feedback_parts.append(f"Version incremented to {version_label}")
        else:
            feedback_parts.append(f"Version is still {version_label} (expected > 1.0)")
    except:
        # If version is not float-parsable, we give benefit of doubt if content matches
        feedback_parts.append(f"Version label format unknown: {version_label}")

    # Criterion 3: Content Match
    if content_match:
        score += 30
        feedback_parts.append("Content matches final version")
    elif content_is_draft:
        feedback_parts.append("Content is still Draft")
    else:
        feedback_parts.append("Content does not match expected")

    # Criterion 4: No Duplicates
    if count == 1:
        score += 20
        feedback_parts.append("Clean file history (no duplicates)")
    else:
        feedback_parts.append(f"Found {count} files matching name (duplicates created?)")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }