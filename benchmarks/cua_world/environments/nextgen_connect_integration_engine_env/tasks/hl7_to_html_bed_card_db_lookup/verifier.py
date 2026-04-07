#!/usr/bin/env python3
"""
Verifier for hl7_to_html_bed_card_db_lookup task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hl7_to_html_bed_card_db_lookup(traj, env_info, task_info):
    """
    Verify the bed card generator task.
    
    Criteria:
    1. Channel exists and is deployed (Started).
    2. Active test: Sending an HL7 message produced a file.
    3. The file output name matches the [LastName]_[MRN].html pattern.
    4. CRITICAL: The content contains the Database-looked-up name ("Dr. Lisa Cuddy"),
       NOT just the ID from the message ("DOC202").
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Channel Status (10 pts)
    channel_found = result.get("channel_found", False)
    channel_status = result.get("channel_status", "UNKNOWN")
    
    if channel_found:
        score += 5
        feedback_parts.append("Channel 'Bed_Card_Generator' found.")
        if channel_status in ["STARTED", "DEPLOYED"]:
            score += 5
            feedback_parts.append(f"Channel is active ({channel_status}).")
        else:
            feedback_parts.append(f"Channel found but status is {channel_status} (expected STARTED).")
    else:
        feedback_parts.append("Channel 'Bed_Card_Generator' NOT found.")

    # 2. File Generation (Test Message) (30 pts)
    file_created = result.get("test_file_created", False)
    if file_created:
        score += 30
        feedback_parts.append("Success: Channel generated an output file from the test message.")
    else:
        feedback_parts.append("Fail: No output file generated from the test HL7 message.")

    # 3. HTML Validity (20 pts)
    html_valid = result.get("html_structure_valid", False)
    if html_valid:
        score += 20
        feedback_parts.append("Success: Output file contains HTML tags.")
    elif file_created:
        feedback_parts.append("Partial: File created but does not look like valid HTML.")

    # 4. Database Enrichment Verification (40 pts)
    # This is the most critical check. Did they actually query the DB?
    # The test message had DOC202. The DB has DOC202 = Dr. Lisa Cuddy.
    # The output file MUST contain "Dr. Lisa Cuddy".
    lookup_success = result.get("doctor_name_found_in_html", False)
    
    if lookup_success:
        score += 40
        feedback_parts.append("Success: Database lookup confirmed! Found 'Dr. Lisa Cuddy' in output.")
    elif file_created:
        feedback_parts.append("Fail: Database lookup failed. 'Dr. Lisa Cuddy' not found in output card.")
        feedback_parts.append("Make sure you are querying the 'doctors' table using the ID from PV1-7.1.")

    passed = (score >= 80) and lookup_success

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }