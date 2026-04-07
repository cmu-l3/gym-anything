#!/usr/bin/env python3
"""
Verifier for hl7_adt_csv_export task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hl7_adt_csv_export(traj, env_info, task_info):
    """
    Verifies the agent successfully created a channel to export HL7 ADT data to CSV.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_header = metadata.get('expected_header', "PatientID,LastName,FirstName,DOB,Gender,Street,City,State,Zip,Phone,SSN")
    
    # Retrieve result from container
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

    # Extract metrics
    score = 0
    feedback_parts = []
    
    channel_id = result.get('channel_id', "")
    channel_status = result.get('channel_status', "UNKNOWN")
    listener_port_check = result.get('listener_port_check', "FALSE")
    messages_sent = result.get('messages_sent', 0)
    output_exists = result.get('output_file_exists', False)
    header_found = result.get('header_found', False)
    file_content = result.get('file_content_preview', "")
    task_start = result.get('task_start_time', 0)
    file_timestamp = result.get('output_file_timestamp', 0)

    # Scoring Logic
    
    # 1. Channel Created (10 pts)
    if channel_id:
        score += 10
        feedback_parts.append("Channel 'ADT_CSV_Export' created.")
    else:
        feedback_parts.append("Channel 'ADT_CSV_Export' not found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback_parts)}

    # 2. Channel Running & Port Correct (20 pts)
    if channel_status == "STARTED":
        score += 10
        feedback_parts.append("Channel is deployed and running.")
    else:
        feedback_parts.append(f"Channel status is {channel_status} (expected STARTED).")
        
    if listener_port_check == "TRUE":
        score += 10
        feedback_parts.append("Listener configured on correct port 6661.")
    else:
        feedback_parts.append("Listener NOT on port 6661.")

    # 3. Output File Existence & Timestamp (10 pts)
    # Anti-gaming: File must be created AFTER task start
    if output_exists:
        if file_timestamp > task_start:
            score += 10
            feedback_parts.append("Output file created during task execution.")
        else:
            feedback_parts.append("Output file exists but timestamp predates task start (stale data).")
    else:
        feedback_parts.append("Output CSV file not created.")

    # 4. CSV Header Verification (10 pts)
    if header_found:
        score += 10
        feedback_parts.append("CSV Header row matches requirements.")
    else:
        feedback_parts.append("CSV Header missing or incorrect.")

    # 5. Content Verification (50 pts)
    # Check if the extracted data from test messages matches expected
    # The export script sends 3 messages. We look for extracted rows in file_content.
    
    expected_rows = [
        "MRN10045,JOHNSON,ROBERT,19650312,M,456 OAK AVE,SPRINGFIELD,IL,62704,2175551234,123456789",
        "MRN20078,MARTINEZ,MARIA,19780925,F,789 PINE ST,CHICAGO,IL,60601,3125559876,987654321",
        "MRN30112,CHEN,WILLIAM,19900508,M,321 MAPLE DR,PEORIA,IL,61602,3095554567,456789123"
    ]
    
    matched_rows = 0
    if file_content:
        for row in expected_rows:
            # Simple substring check is usually sufficient if CSV formatting is standard
            if row in file_content:
                matched_rows += 1
    
    # Normalize score based on matches (Max 50)
    # 3 messages sent. If all 3 match -> 50. 
    # Partial credit: 15 pts per row.
    
    row_score = matched_rows * 15
    if matched_rows == 3: row_score = 50 # Bonus for perfection
    score += row_score
    
    if matched_rows > 0:
        feedback_parts.append(f"Correctly processed {matched_rows}/3 test messages.")
    else:
        feedback_parts.append("No correct data rows found in output CSV.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }