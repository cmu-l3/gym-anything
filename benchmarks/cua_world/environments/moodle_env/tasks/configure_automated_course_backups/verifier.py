#!/usr/bin/env python3
"""Verifier for Configure Automated Course Backups task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_backup_settings(traj, env_info, task_info):
    """
    Verify Moodle automated backup settings.
    
    Criteria (100 points total):
    1. Automated backups enabled (20 pts)
    2. Schedule is Sat + Sun (20 pts)
    3. Execution time is 03:00 (10 pts)
    4. Storage path is correct (20 pts)
    5. Storage type is 'Specified directory' (10 pts)
    6. Retention is 4 backups (10 pts)
    7. Delete old backups enabled (5 pts)
    8. Skip hidden enabled (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/backup_config_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []
    
    # 1. Active (Enabled)
    # Value '1' means enabled
    if str(result.get('backup_auto_active')) == '1':
        score += 20
        feedback.append("Backups enabled")
    else:
        feedback.append("Backups NOT enabled")

    # 2. Weekdays
    # Moodle stores this as a string of days, often "Saturday, Sunday" or a bitmask/concatenation depending on version.
    # Common format in config_plugins is often a string "0000011" (MTWTFSS) or "Saturday, Sunday".
    # We will check if it contains Saturday and Sunday indicators.
    weekdays = str(result.get('backup_auto_weekdays', '')).lower()
    
    # Heuristic: Check for common patterns
    # Pattern A: Comma separated "Saturday, Sunday"
    # Pattern B: Binary string (Mon=0...Sun=6). Sat=5, Sun=6. "0000011"
    sat_found = 'sat' in weekdays or (len(weekdays) == 7 and weekdays[5] == '1')
    sun_found = 'sun' in weekdays or (len(weekdays) == 7 and weekdays[6] == '1')
    
    # Strict check: ONLY Sat and Sun. 
    # If binary string: "0000011"
    # If text: shouldn't contain "mon", "tue", etc.
    others_found = any(d in weekdays for d in ['mon', 'tue', 'wed', 'thu', 'fri'])
    if len(weekdays) == 7:
        others_found = any(weekdays[i] == '1' for i in range(5))

    if sat_found and sun_found and not others_found:
        score += 20
        feedback.append("Schedule correct (Sat, Sun)")
    elif sat_found and sun_found:
        score += 10
        feedback.append("Schedule includes Sat/Sun but also other days")
    else:
        feedback.append(f"Schedule incorrect (Value: {weekdays})")

    # 3. Hour (3 AM)
    hour = str(result.get('backup_auto_hour'))
    if hour == '3':
        score += 10
        feedback.append("Time correct (03:00)")
    else:
        feedback.append(f"Time incorrect ({hour}:00)")

    # 4. Storage Type
    # 0 = course area, 1 = specified directory, 2 = both
    # Requirement: "stored in a dedicated directory rather than the default" -> 1 is preferred, 2 technically meets requirement of storing there but duplicates.
    # Strict reading: "rather than" implies exclusion of default. So 1 is correct.
    storage = str(result.get('backup_auto_storage'))
    if storage == '1':
        score += 10
        feedback.append("Storage type correct (Directory only)")
    elif storage == '2':
        score += 5
        feedback.append("Storage type: Directory + Course area (Partial credit)")
    else:
        feedback.append(f"Storage type incorrect (Value: {storage})")

    # 5. Storage Path
    dest = str(result.get('backup_auto_destination', '')).strip()
    expected_path = '/var/moodledata/backups_auto'
    if dest == expected_path:
        score += 20
        feedback.append("Destination path correct")
    else:
        feedback.append(f"Destination path incorrect ('{dest}')")

    # 6. Retention
    keep = str(result.get('backup_auto_keep'))
    if keep == '4':
        score += 10
        feedback.append("Retention correct (4)")
    else:
        feedback.append(f"Retention incorrect ({keep})")

    # 7. Delete old
    delete_old = str(result.get('backup_auto_delete_old'))
    if delete_old == '1':
        score += 5
        feedback.append("Delete old enabled")
    else:
        feedback.append("Delete old disabled")

    # 8. Skip hidden
    skip_hidden = str(result.get('backup_auto_skip_hidden'))
    if skip_hidden == '1':
        score += 5
        feedback.append("Skip hidden enabled")
    else:
        feedback.append("Skip hidden disabled")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback)
    }