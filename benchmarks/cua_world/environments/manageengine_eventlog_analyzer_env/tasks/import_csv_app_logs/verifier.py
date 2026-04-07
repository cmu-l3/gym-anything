#!/usr/bin/env python3
"""
Verifier for import_csv_app_logs task.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_csv_app_logs(traj, env_info, task_info):
    """
    Verify CSV log import.
    
    Criteria:
    1. Events from CSV exist in DB (Total count increased).
    2. Specific "Error" event found.
    3. Source field mapped correctly to "PAYROLL-DB".
    4. Severity field mapped correctly (String match or standard syslog level check).
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
    
    initial_count = int(result.get("initial_count", 0))
    total_imported = int(result.get("total_imported", 0))
    # ELA DB Query returns pipe-separated values: SEVERITY|SOURCE|MESSAGE
    raw_record = result.get("db_record_raw", "").strip()
    
    # 1. Check Ingestion (40 pts)
    new_events = total_imported - initial_count
    if new_events >= 3: # We expect ~5 events
        score += 40
        feedback_parts.append(f"Successfully imported {new_events} events")
    elif new_events > 0:
        score += 20
        feedback_parts.append(f"Imported partial events ({new_events})")
    else:
        feedback_parts.append("No new events found in database")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check Field Mapping (60 pts)
    # Parse the raw record
    severity_val = ""
    source_val = ""
    message_val = ""
    
    if raw_record:
        parts = raw_record.split('|')
        if len(parts) >= 3:
            severity_val = parts[0].strip()
            source_val = parts[1].strip()
            message_val = parts[2].strip()
    
    # Check Source (20 pts)
    if "PAYROLL-DB" in source_val:
        score += 20
        feedback_parts.append("Source mapped correctly")
    else:
        feedback_parts.append(f"Source mapping incorrect (Found: '{source_val}')")
        
    # Check Severity (20 pts)
    # ELA might store as int (1-7) or string ("Error"). 
    # Syslog: Error=3. ELA sometimes uses 1=Info, etc. 
    # We accept "Error", "ERROR", "3", or "Critical" (if mapped aggressively).
    valid_severities = ["Error", "ERROR", "3", "Critical", "CRITICAL"]
    if any(x in severity_val for x in valid_severities):
        score += 20
        feedback_parts.append("Severity mapped correctly")
    else:
        feedback_parts.append(f"Severity mapping incorrect (Found: '{severity_val}', Expected Error/3)")

    # Check Message (20 pts)
    if "Database connection lost" in message_val:
        score += 20
        feedback_parts.append("Message content preserved")
    else:
        feedback_parts.append("Message content missing or malformed")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }