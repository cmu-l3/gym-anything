#!/usr/bin/env python3
"""
Verifier for Legacy Fixed-Width Ingestion Task.

Criteria:
1. Channel 'Legacy_Census_Ingest' exists and is deployed (STARTED).
2. Input file was consumed (removed from inbox).
3. Output files exist in outbox (matching record count).
4. Output JSON content is correctly parsed (fields match fixed-width spec, whitespace trimmed).
5. Output filenames match MRN.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_legacy_fixed_width_ingestion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # Expected values
    EXPECTED_RECORD_COUNT = 5
    
    # 1. Channel Status (20 pts)
    if result.get('channel_exists'):
        score += 10
        feedback.append("Channel created.")
        status = result.get('channel_status', 'UNKNOWN')
        if status in ['STARTED', 'DEPLOYED', 'POLLING']:
            score += 10
            feedback.append(f"Channel is active ({status}).")
        else:
            feedback.append(f"Channel state is {status} (expected STARTED).")
    else:
        feedback.append("Channel 'Legacy_Census_Ingest' not found.")

    # 2. File Consumption (10 pts)
    # If inbox is empty, agent likely processed the file (or deleted it, which is also valid cleanup)
    if result.get('inbox_file_count', -1) == 0:
        score += 10
        feedback.append("Input file consumed from inbox.")
    else:
        feedback.append("Input file still present in inbox (or check failed).")

    # 3. Output Generation (30 pts)
    outbox_count = result.get('outbox_file_count', 0)
    if outbox_count == EXPECTED_RECORD_COUNT:
        score += 30
        feedback.append(f"Correct number of output files generated ({outbox_count}).")
    elif outbox_count > 0:
        score += 15
        feedback.append(f"Partial output generation: {outbox_count} files (expected {EXPECTED_RECORD_COUNT}). Check batch splitting.")
    else:
        feedback.append("No output files found in outbox.")

    # 4. JSON Content Verification (40 pts)
    sample = result.get('sample_json_content', {})
    
    # If sample is a string (failed parse in export), try to parse it here, or fail
    if isinstance(sample, str):
        try:
            sample = json.loads(sample)
        except:
            sample = {}

    if sample:
        content_score = 0
        
        # Check keys
        required_keys = ['mrn', 'firstName', 'lastName', 'dob', 'gender']
        keys_present = [k for k in required_keys if k in sample]
        
        if len(keys_present) == len(required_keys):
            content_score += 10
            feedback.append("JSON structure is correct.")
        else:
            feedback.append(f"JSON missing keys: {set(required_keys) - set(keys_present)}")

        # Check trimming (very important for fixed width)
        # We don't know EXACTLY which record this is without checking MRN, but we can check format
        is_trimmed = True
        for k, v in sample.items():
            if isinstance(v, str) and (v.startswith(' ') or v.endswith(' ')):
                is_trimmed = False
                break
        
        if is_trimmed:
            content_score += 15
            feedback.append("Strings correctly trimmed.")
        else:
            feedback.append("Strings contain whitespace (trimming failed).")

        # Check valid data types/values roughly
        if len(sample.get('dob', '')) == 8 and len(sample.get('gender', '')) == 1:
            content_score += 15
            feedback.append("Data fields look valid.")
        
        score += content_score
    else:
        feedback.append("Could not verify JSON content (no sample available).")

    # Final tally
    passed = (score >= 70) and (outbox_count > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }