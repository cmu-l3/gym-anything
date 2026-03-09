#!/usr/bin/env python3
"""Verifier for enforce_copyright_headers task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enforce_copyright_headers(traj, env_info, task_info):
    """
    Verify that copyright headers were configured and applied correctly.

    Criteria:
    1. Java files contain the correct license text (50 pts)
       - Must contain "Copyright (c) 2026 OpenInventory Contributors"
       - Must contain Apache 2.0 reference
    2. IntelliJ Project Configuration exists (30 pts)
       - .idea/copyright/ settings exist
    3. Code compiles (10 pts)
       - Headers must be comments, not invalid syntax
    4. Text Accuracy (10 pts)
       - Exact match for Year and Owner
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
    
    # Metadata requirements
    required_year = "2026"
    required_owner = "OpenInventory Contributors"
    required_url = "http://www.apache.org/licenses/LICENSE-2.0"

    # --- Criterion 1: Headers Applied (50 pts) ---
    file_contents = result.get("file_contents", {})
    files_checked = 0
    files_passed = 0
    
    for filename, content in file_contents.items():
        files_checked += 1
        # Check for standard comment block start
        has_comment = content.strip().startswith("/*") or content.strip().startswith("//")
        
        # Check for key phrases
        has_year_owner = f"Copyright (c) {required_year} {required_owner}" in content
        has_license_ref = "Apache License, Version 2.0" in content
        
        if has_comment and has_year_owner and has_license_ref:
            files_passed += 1
        else:
            logger.info(f"File {filename} failed checks. Comment: {has_comment}, Owner: {has_year_owner}, Lic: {has_license_ref}")

    if files_checked > 0 and files_passed == files_checked:
        score += 50
        feedback_parts.append(f"All {files_checked} checked files have correct headers")
    elif files_passed > 0:
        partial_score = int(50 * (files_passed / files_checked))
        score += partial_score
        feedback_parts.append(f"Only {files_passed}/{files_checked} files have headers")
    else:
        feedback_parts.append("No files contain the required copyright header")

    # --- Criterion 2: Config Persistence (30 pts) ---
    config_exists = result.get("copyright_config_exists", False)
    profile_content = result.get("copyright_profile_content")
    
    if config_exists and profile_content:
        # Check if the profile actually contains the text
        if required_owner in str(profile_content):
            score += 30
            feedback_parts.append("Copyright profile configured and persisted correctly")
        else:
            score += 15
            feedback_parts.append("Copyright profile exists but text mismatch/empty")
    else:
        feedback_parts.append("No IntelliJ Copyright profile found (did you save settings?)")

    # --- Criterion 3: Compilation (10 pts) ---
    if result.get("compile_success", False):
        score += 10
        feedback_parts.append("Project compiles successfully")
    else:
        feedback_parts.append("Project failed to compile (headers might be malformed)")

    # --- Criterion 4: Text Accuracy (10 pts) ---
    # This is slightly redundant with Crit 1 but emphasizes exactness
    # We check if the URL is present exactly as requested
    url_found = False
    for content in file_contents.values():
        if required_url in content:
            url_found = True
            break
            
    if url_found:
        score += 10
        feedback_parts.append("License text details (URL) match exactly")
    else:
        feedback_parts.append("License URL missing or incorrect")

    # Final tally
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }