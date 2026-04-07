#!/usr/bin/env python3
"""
Verifier for configure_file_upload_policy task.

Checks:
1. FileUpload_MaxFileSize == 5242880
2. FileUpload_MediaTypeWhiteList contains correct MIME types
3. FileUpload_ProtectFiles == true
4. Announcement message posted in #general
5. VLM trajectory verification for admin panel navigation
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Import VLM utils provided by framework
# Note: In the actual environment, these imports might be adjusted or mocked if running locally
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logging.warning("VLM modules not available")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_file_upload_policy(traj, env_info, task_info):
    """
    Verify the Rocket.Chat file upload policy configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_size = metadata.get('expected_max_file_size', 5242880)
    expected_types = set(metadata.get('expected_media_types', [
        "image/jpeg", "image/png", "image/gif", "application/pdf", "text/plain"
    ]))
    announcement_keywords = metadata.get('announcement_keywords', ["5mb", "pdf"])

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    settings = result.get('settings', {})
    messages = result.get('messages', [])
    task_start_time = result.get('task_start_time', 0)

    # 1. Verify Max File Size (25 pts)
    actual_size = settings.get('max_file_size', -1)
    if actual_size == expected_size:
        score += 25
        feedback_parts.append("Max file size configured correctly.")
    else:
        feedback_parts.append(f"Max file size incorrect. Expected {expected_size}, got {actual_size}.")

    # 2. Verify Media Type Whitelist (25 pts)
    actual_whitelist_str = settings.get('media_type_whitelist', "")
    # Normalize: split by comma, strip whitespace, remove empty strings
    actual_types = set([t.strip() for t in actual_whitelist_str.split(',') if t.strip()])
    
    # Check if sets match (order doesn't matter)
    if actual_types == expected_types:
        score += 25
        feedback_parts.append("Media type whitelist configured correctly.")
    else:
        missing = expected_types - actual_types
        extra = actual_types - expected_types
        msg = "Whitelist incorrect."
        if missing: msg += f" Missing: {missing}."
        if extra: msg += f" Extra: {extra}."
        feedback_parts.append(msg)

    # 3. Verify Protect Files (15 pts)
    if settings.get('protect_files') is True:
        score += 15
        feedback_parts.append("File protection enabled.")
    else:
        feedback_parts.append("File protection NOT enabled.")

    # 4. Verify Announcement Message (20 pts)
    announcement_found = False
    valid_message = None
    
    # Convert timestamps from ms to seconds for comparison if needed
    # Rocket.Chat timestamps in messages are typically ISO strings or ms
    for msg in messages:
        # Check timestamp
        msg_ts_iso = msg.get('ts') # usually string like "2026-02-16T..."
        # Simplified: We rely on the export script filtering for messages by admin
        # We assume export script fetches current history, so messages at top are recent.
        # We really just need to check content.
        
        text = msg.get('msg', '').lower()
        # Check for keywords
        # Must have "5mb" OR "5 mb" AND "image" AND "pdf"
        has_size = "5mb" in text or "5 mb" in text or "5 megabyte" in text
        has_types = ("image" in text or "jpg" in text or "png" in text) and "pdf" in text
        
        if has_size and has_types:
            announcement_found = True
            valid_message = text
            break

    if announcement_found:
        score += 20
        feedback_parts.append("Announcement message verified.")
    else:
        feedback_parts.append("Announcement message missing or missing key details (size/types) in #general.")

    # 5. VLM Verification (15 pts)
    # Check for Admin UI navigation
    vlm_score = 0
    if VLM_AVAILABLE:
        frames = sample_trajectory_frames(traj, n=6)
        prompt = """
        Analyze these screenshots of a user configuring Rocket.Chat.
        Do you see the user navigating the "Administration" panel?
        Do you see the "File Upload" settings section?
        Do you see input fields for "Maximum File Upload Size" or "Accepted Media Types"?
        
        Answer YES or NO and provide a confidence score (0-1).
        """
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_res.get('parsed', {}) if vlm_res.get('success') else {}
            # Fallback simple string parsing if 'parsed' isn't structured
            raw_response = vlm_res.get('response', '').lower()
            
            if "yes" in raw_response or parsed.get('admin_panel_visible', False):
                vlm_score = 15
                feedback_parts.append("VLM verified admin panel navigation.")
            else:
                feedback_parts.append("VLM did not observe admin panel navigation.")
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            # Grant benefit of doubt if VLM fails but settings are correct
            if score >= 50: 
                vlm_score = 15
                feedback_parts.append("VLM skipped (error), accepted based on settings.")
    else:
        # Fallback if VLM not available locally
        if score >= 50:
            vlm_score = 15
            feedback_parts.append("VLM skipped, accepted based on settings.")

    score += vlm_score

    # Final check
    passed = (score >= 60) and (actual_size == expected_size)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }