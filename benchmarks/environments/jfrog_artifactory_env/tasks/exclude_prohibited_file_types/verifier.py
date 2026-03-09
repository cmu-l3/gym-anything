#!/usr/bin/env python3
"""
Verifier for exclude_prohibited_file_types task.

Checks:
1. Valid artifacts (.txt) are still accepted (HTTP 201).
2. Prohibited artifacts (.exe) are rejected (HTTP 403/409).
3. Prohibited artifacts (.dll) are rejected (HTTP 403/409).
4. Repository configuration contains correct exclude patterns.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_exclude_prohibited_file_types(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract HTTP codes
    # Artifactory returns 201 for successful creation
    # Artifactory returns 403 (Forbidden) or 409 (Conflict) for excluded/prohibited uploads
    http_txt = result.get('http_txt', '000').strip()
    http_exe = result.get('http_exe', '000').strip()
    http_dll = result.get('http_dll', '000').strip()
    
    # 1. Verify Valid Artifacts (30 pts)
    # Must be 201 Created
    if http_txt == '201':
        score += 30
        feedback_parts.append("Valid artifacts (.txt) accepted.")
    else:
        feedback_parts.append(f"Valid artifacts (.txt) rejected or failed (HTTP {http_txt}). Check permissions.")

    # 2. Verify .exe Rejection (30 pts)
    # Should be 403 or 409
    if http_exe in ['403', '409']:
        score += 30
        feedback_parts.append("Executable files (.exe) correctly rejected.")
    elif http_exe == '201':
        feedback_parts.append("Executable files (.exe) were NOT rejected (Upload succeeded).")
    else:
        # Some other error (e.g. 500), partial credit if not 201? No, explicit rejection needed.
        feedback_parts.append(f"Executable upload result unexpected (HTTP {http_exe}).")

    # 3. Verify .dll Rejection (30 pts)
    if http_dll in ['403', '409']:
        score += 30
        feedback_parts.append("Library files (.dll) correctly rejected.")
    elif http_dll == '201':
        feedback_parts.append("Library files (.dll) were NOT rejected (Upload succeeded).")
    else:
        feedback_parts.append(f"Library upload result unexpected (HTTP {http_dll}).")

    # 4. Configuration Check (10 pts)
    repo_config = result.get('repo_config', {})
    excludes_pattern = repo_config.get('excludesPattern', '')
    
    # Flexible check: look for substrings
    has_exe = 'exe' in excludes_pattern.lower()
    has_dll = 'dll' in excludes_pattern.lower()
    
    if has_exe and has_dll:
        score += 10
        feedback_parts.append("Configuration verified (Exclude patterns present).")
    else:
        feedback_parts.append(f"Configuration missing required patterns. Found: '{excludes_pattern}'")

    # Calculate Pass/Fail
    # strict pass: functional tests must pass. Config check is supplementary.
    passed = (score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }