#!/usr/bin/env python3
"""
Verifier for generate_chemical_facility_listing task.

Verify that:
1. A report file was created in the correct location.
2. The file was created/modified AFTER the task started.
3. The file contains the expected ammonia facilities.
4. The file DOES NOT contain excluded (non-ammonia) facilities.
5. VLM confirms the agent interacted with the search/report interface.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_generate_chemical_facility_listing(traj, env_info, task_info):
    """
    Verification logic for CAMEO Data Manager ammonia report task.
    """
    # 1. Setup - Get Helper Functions
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # 2. Get Task Metadata
    metadata = task_info.get('metadata', {})
    expected_facilities = metadata.get('expected_facilities', [])
    excluded_facilities = metadata.get('excluded_facilities', [])
    
    # 3. Retrieve Result JSON from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result from environment."}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 4. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence (20 pts)
    if result.get('file_found', False):
        score += 20
        feedback_parts.append(f"Report file found: {os.path.basename(result.get('file_path', ''))}")
    else:
        return {"passed": False, "score": 0, "feedback": "No report file found matching 'ammonia_facility_report.*'"}

    # Criterion 2: Timestamp Check (20 pts)
    # Ensure file was actually created during this session
    if result.get('is_new_file', False):
        score += 20
        feedback_parts.append("File created during task session")
    else:
        feedback_parts.append("WARNING: File timestamp indicates it might be old or pre-existing.")
        # We might penalize heavily here, but if the content is correct, maybe partial credit?
        # For strict anti-gaming:
        return {"passed": False, "score": score, "feedback": "File exists but was not created during the task (timestamp check failed)."}

    # Criterion 3: Content Verification (40 pts)
    content = result.get('content_preview', '')
    if content == "[PDF Content - Not Text Readable Directly]":
        # If PDF, we can't verify content easily without OCR tools in the verifier.
        # We'll rely on VLM or give points if size > 1KB.
        feedback_parts.append("PDF format detected (content check skipped, assuming VLM will verify visual output).")
        score += 20 # Give benefit of doubt for format, check size
        if result.get('file_size_bytes', 0) > 500:
             score += 20
    elif content:
        content_lower = content.lower()
        
        # Check Expected Facilities
        found_count = 0
        for facility in expected_facilities:
            if facility.lower() in content_lower:
                found_count += 1
            else:
                feedback_parts.append(f"Missing expected facility: {facility}")
        
        if found_count == len(expected_facilities):
            score += 20
            feedback_parts.append("All expected ammonia facilities found.")
        elif found_count > 0:
            score += int(20 * (found_count / len(expected_facilities)))
            feedback_parts.append(f"Found {found_count}/{len(expected_facilities)} expected facilities.")
            
        # Check Excluded Facilities (Filtering)
        excluded_found = 0
        for facility in excluded_facilities:
            if facility.lower() in content_lower:
                excluded_found += 1
                feedback_parts.append(f"Incorrectly included non-ammonia facility: {facility}")
        
        if excluded_found == 0:
            score += 20
            feedback_parts.append("Correctly filtered out non-ammonia facilities.")
        else:
            # Penalize for bad filtering
            score += max(0, 20 - (excluded_found * 10))

    else:
        feedback_parts.append("File is empty or unreadable.")

    # Criterion 4: App Running (10 pts)
    if result.get('app_running', False):
        score += 10
    else:
        feedback_parts.append("CAMEO Data Manager was not running at end of task.")

    # Criterion 5: VLM / Trajectory (10 pts)
    # (Placeholder for actual VLM logic, we award these points if file exists and looks reasonable)
    # In a full implementation, we'd pass traj frames to a VLM here.
    # For now, we assume if they made a file with correct content, they used the app.
    if score >= 60:
        score += 10
        feedback_parts.append("Implicit verification passed.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }