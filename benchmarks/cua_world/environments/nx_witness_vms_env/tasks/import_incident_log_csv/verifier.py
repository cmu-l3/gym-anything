#!/usr/bin/env python3
"""
Verifier for import_incident_log_csv task.

Verifies:
1. Bookmarks created in Nx Witness match the CSV rows.
2. Correct mapping of Camera Name -> Device ID.
3. Correct metadata (Name, Description).
4. Correct timestamp conversion (ISO -> Milliseconds).
"""

import json
import os
import base64
import datetime
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_csv_content(b64_content):
    """Decodes base64 CSV and returns list of dicts."""
    try:
        content = base64.b64decode(b64_content).decode('utf-8')
        lines = content.strip().split('\n')
        headers = [h.strip() for h in lines[0].split(',')]
        data = []
        for line in lines[1:]:
            if not line.strip(): continue
            values = [v.strip() for v in line.split(',')]
            row = dict(zip(headers, values))
            data.append(row)
        return data
    except Exception as e:
        logger.error(f"Failed to parse CSV: {e}")
        return []

def iso_to_ms(iso_str):
    """Converts ISO 8601 string to epoch milliseconds."""
    try:
        # Expected format: 2026-03-08T08:15:00
        dt = datetime.datetime.strptime(iso_str, "%Y-%m-%dT%H:%M:%S")
        return int(dt.timestamp() * 1000)
    except ValueError:
        return 0

def verify_import_incident_log(traj, env_info, task_info):
    """
    Verify the agent imported CSV events as bookmarks correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    task_start = result.get("task_start_timestamp", 0)
    csv_rows = parse_csv_content(result.get("csv_content_base64", ""))
    bookmarks = result.get("bookmarks", [])
    devices = result.get("devices", [])
    script_found = result.get("script_found", False)

    if not csv_rows:
        return {"passed": False, "score": 0, "feedback": "Could not read verification data (CSV empty)"}

    # Build Map: Camera Name -> Device ID
    name_to_id = {}
    for d in devices:
        name_to_id[d.get("name")] = d.get("id")

    score = 0
    feedback_parts = []
    
    # Track matches
    matches = 0
    total_expected = len(csv_rows)
    
    # Criteria Points
    # 20 pts: Script/Evidence found
    # 80 pts: Data Accuracy (20 pts per correct row, scaled)
    
    if script_found:
        score += 20
        feedback_parts.append("Script/evidence found (+20)")
    else:
        feedback_parts.append("No script file found")

    # Verify each CSV row has a corresponding bookmark
    valid_bookmarks = 0
    
    for row in csv_rows:
        cam_name = row.get("Camera Name")
        event_type = row.get("Event Type")
        user = row.get("User")
        timestamp_iso = row.get("Timestamp")
        duration_sec = int(row.get("Duration_Sec", 0))
        
        expected_time_ms = iso_to_ms(timestamp_iso)
        expected_duration_ms = duration_sec * 1000
        expected_desc = f"User: {user}"
        
        target_dev_id = name_to_id.get(cam_name)
        if not target_dev_id:
            feedback_parts.append(f"Setup Error: Camera '{cam_name}' not found in system")
            continue

        # Look for a matching bookmark
        # Match criteria: 
        # 1. Correct Device ID
        # 2. Correct Name (Event Type)
        # 3. Start Time within +/- 2000ms (allow slight drift/conversion diffs)
        
        found = False
        for bk in bookmarks:
            # Check if this bookmark was created RECENTLY (anti-gaming, must be > task_start - buffer)
            # Actually, Nx 'creationTimestampMs' might be internal, but we can check if it exists in the list
            # Since we assume the agent created it, we trust the export script dump.
            # Real anti-gaming is verifying the bookmark exists NOW.
            
            b_name = bk.get("name", "")
            b_desc = bk.get("description", "")
            b_start = int(bk.get("startTimeMs", 0))
            b_dev_id = bk.get("_deviceId", "")
            
            # Check Device
            if b_dev_id != target_dev_id:
                continue
                
            # Check Name
            if b_name != event_type:
                continue
            
            # Check Time (tolerance 5 seconds to be generous with timezones/conversions)
            if abs(b_start - expected_time_ms) > 5000:
                continue
            
            # Check Description
            if expected_desc not in b_desc:
                continue
                
            found = True
            break
        
        if found:
            valid_bookmarks += 1
        else:
            feedback_parts.append(f"Missing/Incorrect bookmark for '{event_type}' on '{cam_name}'")

    # Calculate Data Score (max 80)
    if total_expected > 0:
        data_score = int((valid_bookmarks / total_expected) * 80)
        score += data_score
        feedback_parts.append(f"Bookmarks Matched: {valid_bookmarks}/{total_expected} (+{data_score})")

    passed = (valid_bookmarks == total_expected) and (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }