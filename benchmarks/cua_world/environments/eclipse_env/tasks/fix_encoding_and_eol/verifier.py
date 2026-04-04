#!/usr/bin/env python3
"""Verifier for fix_encoding_and_eol task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fix_encoding_and_eol(traj, env_info, task_info):
    """Verify that line endings were converted and encoding was fixed.

    Criteria:
    1. WindowsService.java has NO CRLF characters (Unix format) (40 pts)
    2. Project encoding is set to UTF-8 (40 pts)
    3. Files still exist and are not empty (10 pts)
    4. VLM Verification of UI state (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Read result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # --- Criterion 1: Line Endings (40 points) ---
    has_crlf = result.get('has_crlf', True)
    java_exists = result.get('java_file_exists', False)
    
    if java_exists:
        if not has_crlf:
            score += 40
            feedback_parts.append("Line endings converted to Unix (LF)")
        else:
            feedback_parts.append("File still contains Windows line endings (CRLF)")
    else:
        feedback_parts.append("Java file missing")

    # --- Criterion 2: Project Encoding (40 points) ---
    encoding_setting = result.get('encoding_setting', '').upper()
    
    if encoding_setting == 'UTF-8':
        score += 40
        feedback_parts.append("Project encoding correctly set to UTF-8")
    elif encoding_setting == 'ISO-8859-1':
        feedback_parts.append("Project encoding still set to ISO-8859-1 (default)")
    else:
        feedback_parts.append(f"Project encoding set to unexpected value: {encoding_setting}")

    # --- Criterion 3: Data Integrity (10 points) ---
    java_size = result.get('java_size', 0)
    prop_size = result.get('prop_size', 0)
    
    if java_size > 50 and prop_size > 10:
        score += 10
        feedback_parts.append("Files preserved")
    else:
        feedback_parts.append("Files appear to be empty or corrupted")

    # --- Criterion 4: VLM Verification (10 points) ---
    # We check if the agent opened the properties dialog or file menu
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Convert line endings to Unix and change project encoding to UTF-8",
            checklist_items=[
                "Eclipse IDE is open",
                "Properties dialog or Resource settings visible",
                "Line Delimiters conversion menu used",
                "Japanese characters visible correctly in editor (not garbage)"
            ]
        )
        
        if vlm_result:
            # We add points if VLM thinks it passed, but don't fail based solely on it
            if vlm_result.get('vlm_passed', False):
                score += 10
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Default points if VLM fails to run to avoid penalizing for infra issues
        score += 10 

    # Cap score at 100
    score = min(score, 100)
    
    # Must have fixed both issues to pass
    passed = (not has_crlf) and (encoding_setting == 'UTF-8') and (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }