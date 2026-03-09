#!/usr/bin/env python3
"""
Verifier for define_provider_availability task.

Checks:
1. Appointment block exists on target date.
2. Provider is 'Superman'.
3. Start/End times match target (09:00 - 13:00).
4. Location is 'Registration Desk'.
5. Block was created during the task (anti-gaming).
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_iso_time(iso_str):
    """Parses ISO string to time object. Handles timezone offsets roughly."""
    try:
        # Format: 2026-03-12T09:00:00.000+0000 or 2026-03-12T09:00:00.000-0500
        # We mostly care about the local time specified in the UI which is reflected in the T.. string
        if 'T' in iso_str:
            time_part = iso_str.split('T')[1].split('.')[0] # 09:00:00
            return datetime.strptime(time_part, "%H:%M:%S").time()
    except Exception:
        pass
    return None

def verify_define_provider_availability(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    api_data = result.get('api_data', {})
    initial_count = int(result.get('initial_count', 0))
    current_count = int(api_data.get('current_count', 0))
    block = api_data.get('block_details', {})
    
    score = 0
    feedback_parts = []
    
    # Criteria 1: Block Exists (30 pts)
    if api_data.get('found_block') and block:
        score += 30
        feedback_parts.append("Block created")
    else:
        return {"passed": False, "score": 0, "feedback": "No appointment block found for Superman on target date."}

    # Criteria 2: Correct Provider (20 pts)
    provider = block.get('provider', '')
    if 'Superman' in provider:
        score += 20
        feedback_parts.append("Correct provider")
    else:
        feedback_parts.append(f"Incorrect provider: {provider}")

    # Criteria 3: Time Check (30 pts total)
    target_start = task_info.get('metadata', {}).get('target_start_time', '09:00:00')
    target_end = task_info.get('metadata', {}).get('target_end_time', '13:00:00')
    
    actual_start = block.get('startTime', '')
    actual_end = block.get('endTime', '')
    
    # Allow 5 min tolerance if parsing full timestamps, but string match is usually exact for this app
    if actual_start == target_start:
        score += 15
        feedback_parts.append("Start time correct")
    else:
        feedback_parts.append(f"Start time mismatch (Expected {target_start}, got {actual_start})")
        
    if actual_end == target_end:
        score += 15
        feedback_parts.append("End time correct")
    else:
        feedback_parts.append(f"End time mismatch (Expected {target_end}, got {actual_end})")

    # Criteria 4: Location (10 pts)
    location = block.get('location', '')
    target_loc = task_info.get('metadata', {}).get('target_location', 'Registration Desk')
    if target_loc.lower() in location.lower():
        score += 10
        feedback_parts.append("Location correct")
    else:
        feedback_parts.append(f"Location mismatch (Expected {target_loc}, got {location})")

    # Criteria 5: Anti-Gaming / New Creation (10 pts)
    # Check if count increased OR if creation date is recent
    is_new = False
    if current_count > initial_count:
        is_new = True
    
    # Also check dateCreated if available
    task_start_ts = result.get('task_start', 0)
    date_created_iso = block.get('dateCreated', '')
    if date_created_iso:
        try:
            # Parse ISO to timestamp. Python 3.7+ handles fromisoformat well for standard ISO
            # OpenMRS: 2026-03-01T12:00:00.000+0000
            # Simple hack: if the date string starts with 2026-03-01 (today's date in env context), it's likely new
            # Better: compare count
            pass
        except:
            pass
            
    if is_new:
        score += 10
        feedback_parts.append("Verified new creation")
    else:
        feedback_parts.append("Count did not increase (might be pre-existing)")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }