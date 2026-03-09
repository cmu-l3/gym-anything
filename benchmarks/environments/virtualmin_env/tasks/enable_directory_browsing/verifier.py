#!/usr/bin/env python3
"""
Verifier for enable_directory_browsing task.

Scoring Criteria:
1. Directory creation (10 pts)
2. File creation (15 pts) - Anti-gaming: must be created during task
3. HTTP Status 200 OK (40 pts) - Indicates access is allowed
4. File Listing Visible (35 pts) - Indicates "Indexes" is actually working

Total: 100 pts. Pass threshold: 75 pts.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_directory_browsing(traj, env_info, task_info):
    """
    Verify that the directory was created, files exist, and Apache indexes are enabled.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Directory Existence (10 pts)
    if result.get("dir_exists", False):
        score += 10
        feedback_parts.append("Directory '/downloads' created.")
    else:
        feedback_parts.append("Directory '/downloads' NOT found.")

    # 2. File Creation (15 pts)
    # Require all 3 files for full points
    files_count = result.get("files_created_count", 0)
    created_during = result.get("files_created_during_task", False)
    
    if files_count >= 3:
        if created_during:
            score += 15
            feedback_parts.append("All 3 placeholder files created.")
        else:
            score += 5 # Penalty if timestamps look stale (unlikely given setup cleans them, but robust)
            feedback_parts.append("Files exist but timestamps are old.")
    elif files_count > 0:
        score += (files_count * 3) # Partial credit
        feedback_parts.append(f"Only {files_count}/3 files created.")
    else:
        feedback_parts.append("No placeholder files found.")

    # 3. HTTP Accessibility (40 pts)
    http_code = result.get("http_code", 0)
    if http_code == 200:
        score += 40
        feedback_parts.append("HTTP 200 OK: Directory is accessible.")
    elif http_code == 403:
        feedback_parts.append("HTTP 403 Forbidden: Directory browsing NOT enabled.")
    else:
        feedback_parts.append(f"HTTP {http_code}: Unexpected response.")

    # 4. Listing Visibility (35 pts)
    # This confirms that we aren't just serving an empty index.html, but actually listing the files
    listing_visible = result.get("http_listing_visible", False)
    files_in_html = result.get("files_found_in_html", 0)

    if listing_visible:
        score += 35
        feedback_parts.append("File listing confirmed in HTML response.")
    elif files_in_html > 0:
        # Partial credit if some files show up but logic was strict
        score += 15
        feedback_parts.append(f"Partial listing found ({files_in_html}/3 files visible).")
    else:
        feedback_parts.append("File listing NOT visible in HTTP response.")

    # Pass Threshold
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }