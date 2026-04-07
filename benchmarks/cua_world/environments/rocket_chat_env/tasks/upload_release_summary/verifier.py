#!/usr/bin/env python3
"""
Verifier for upload_release_summary task.

Checks:
1. File 'release_summary.csv' exists in the 'release-updates' channel.
2. File was uploaded AFTER the task started (anti-gaming).
3. Message accompanying the file contains required key phrases.
4. File type is CSV.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_upload_release_summary(traj, env_info, task_info):
    """
    Verify upload of release summary CSV with correct message.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_filename = metadata.get('target_filename', 'release_summary.csv')
    required_phrases = metadata.get('required_text_phrases', [])
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic checks
    if not result.get('api_accessible'):
        return {"passed": False, "score": 0, "feedback": "Could not verify: Rocket.Chat API unreachable"}
    
    if not result.get('channel_found'):
        return {"passed": False, "score": 0, "feedback": "Could not find target channel 'release-updates'"}

    task_start_time = result.get('task_start_time', 0)
    channel_files = result.get('channel_files', [])
    channel_messages = result.get('channel_messages', [])

    score = 0
    feedback_parts = []
    
    # Criterion 1: File exists in channel (40 points)
    # Filter files by name
    target_files = [f for f in channel_files if f.get('name') == target_filename]
    
    if not target_files:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"File '{target_filename}' not found in channel 'release-updates'."
        }
    
    score += 40
    feedback_parts.append(f"File '{target_filename}' found in channel")

    # Pick the most recent upload if multiple exist
    # Sort by uploadedAt descending just in case the API sort wasn't perfect
    target_files.sort(key=lambda x: x.get('uploadedAt', ''), reverse=True)
    uploaded_file = target_files[0]
    
    # Criterion 2: Uploaded after task start (15 points)
    uploaded_at_str = uploaded_file.get('uploadedAt')
    # Parse ISO format like "2023-10-27T10:00:00.123Z"
    # Python 3.7+ fromisoformat handles most, but let's be safe with simple string comparison or generic parser
    # Easier: API result usually strictly ordered. We'll use the timestamp check if possible.
    # We'll rely on the export script's timestamp or rough comparison.
    # Here we convert ISO string to timestamp.
    try:
        # cleanup Z if present
        iso_ts = uploaded_at_str.replace('Z', '+00:00')
        dt = datetime.fromisoformat(iso_ts)
        file_ts = dt.timestamp()
        
        if file_ts > task_start_time:
            score += 15
            feedback_parts.append("File uploaded during task session")
        else:
            feedback_parts.append(f"File timestamp ({uploaded_at_str}) is before task start - pre-existing file?")
    except Exception as e:
        logger.warning(f"Timestamp parsing error: {e}")
        # Fallback: if we found the file and it wasn't there at start (implied), give points.
        # But safest is to check timestamp. If parse fails, no points for this criterion.
        feedback_parts.append("Could not verify file timestamp")

    # Criterion 3: File is CSV (10 points)
    # Check mime type or name extension
    mime_type = uploaded_file.get('type', '').lower()
    if 'csv' in mime_type or 'text' in mime_type or target_filename.endswith('.csv'):
        score += 10
        feedback_parts.append("File type/extension is correct")
    else:
        feedback_parts.append(f"Unexpected file type: {mime_type}")

    # Criterion 4: Message text content (35 points)
    # We need to find the message associated with this file or a message sent around the same time
    # Rocket.Chat attaches files to messages. The message object usually contains a 'file' field or we check history.
    
    # Search history for messages that match our requirements
    message_score = 0
    found_msg_text = False
    
    # Strategy: Look for any message sent after start time that contains keywords
    # AND optionally is linked to the file.
    
    matching_messages = []
    for msg in channel_messages:
        msg_ts_str = msg.get('ts', '') # standard RC format is timestamp inside object usually or ISO
        # In RC API history, 'ts' is typically ISO string.
        # We check if message content matches.
        
        text = msg.get('msg', '').lower()
        if not text:
            continue
            
        # Check against required phrases
        # "Release summary for team review - contains recent RC release dates and versions"
        # We'll look for "release summary" and "team review" as critical.
        
        hits = 0
        for phrase in required_phrases:
            if phrase in text:
                hits += 1
        
        if hits >= 2: # Found at least 2 key phrases
            matching_messages.append(msg)
            found_msg_text = True
            break # Stop after finding the first good match (most recent)

    if found_msg_text:
        message_score = 35
        feedback_parts.append("Descriptive message found with required keywords")
    else:
        # Partial credit if they sent *some* message with the file
        # Check if the file object has a message associated in the file list (sometimes implicit)
        # or if there is a message with 'file' attribute matching our file
        file_msg = next((m for m in channel_messages if m.get('file', {}).get('_id') == uploaded_file.get('_id')), None)
        if file_msg and file_msg.get('msg'):
             message_score = 15
             feedback_parts.append("Message present but missing required keywords")
        else:
             feedback_parts.append("No descriptive message found")
    
    score += message_score

    return {
        "passed": score >= 55,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }