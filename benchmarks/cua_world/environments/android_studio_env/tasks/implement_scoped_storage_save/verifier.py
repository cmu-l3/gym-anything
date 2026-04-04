#!/usr/bin/env python3
"""
Verifier for implement_scoped_storage_save task.

This verifier checks:
1. If the project builds successfully (Syntax/Type check).
2. If the legacy code (`Environment.getExternalStorageDirectory`) is removed.
3. If the correct MediaStore APIs (`ContentValues`, `EXTERNAL_CONTENT_URI`, `openOutputStream`) are used.
"""

import json
import logging
import re
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scoped_storage_save(traj, env_info, task_info):
    """
    Verifies that the agent implemented MediaStore saving correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    content = result.get("file_content", "")
    build_success = result.get("build_success", False)
    
    score = 0
    feedback_parts = []
    
    # CRITERION 1: Build Success (30 pts)
    if build_success:
        score += 30
        feedback_parts.append("Project compiles successfully (30/30)")
    else:
        feedback_parts.append("Project build failed (0/30)")

    # CRITERION 2: No Legacy APIs (10 pts)
    # Check for forbidden terms
    legacy_terms = ["getExternalStorageDirectory", "/sdcard/"]
    found_legacy = [term for term in legacy_terms if term in content]
    
    if not found_legacy:
        score += 10
        feedback_parts.append("Legacy storage APIs removed (10/10)")
    else:
        feedback_parts.append(f"Found legacy APIs: {', '.join(found_legacy)} (0/10)")

    # CRITERION 3: MediaStore URI (20 pts)
    if "MediaStore.Images.Media.EXTERNAL_CONTENT_URI" in content or "Images.Media.EXTERNAL_CONTENT_URI" in content:
        score += 20
        feedback_parts.append("Correct MediaStore URI used (20/20)")
    else:
        feedback_parts.append("MediaStore.Images.Media.EXTERNAL_CONTENT_URI not found (0/20)")

    # CRITERION 4: ContentValues & Path (20 pts)
    has_cv = "ContentValues" in content
    # Check for path setting: "Pictures/PhotoStamp"
    has_path = "Pictures/PhotoStamp" in content
    
    if has_cv and has_path:
        score += 20
        feedback_parts.append("ContentValues configured with correct path (20/20)")
    elif has_cv:
        score += 10
        feedback_parts.append("ContentValues used but correct path 'Pictures/PhotoStamp' not found (10/20)")
    else:
        feedback_parts.append("ContentValues not found (0/20)")

    # CRITERION 5: Stream Usage (20 pts)
    # Looking for contentResolver.insert(...) and contentResolver.openOutputStream(...)
    # Allow variations like context.contentResolver
    
    has_insert = re.search(r'contentResolver\.insert', content, re.IGNORECASE)
    has_stream = re.search(r'contentResolver\.openOutputStream', content, re.IGNORECASE)
    
    if has_insert and has_stream:
        score += 20
        feedback_parts.append("Used ContentResolver to insert and open stream (20/20)")
    elif has_insert:
        score += 10
        feedback_parts.append("Inserted content but didn't find openOutputStream (10/20)")
    else:
        feedback_parts.append("ContentResolver insert/stream calls not found (0/20)")

    # Final logic
    passed = score >= 75 and build_success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }