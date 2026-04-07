#!/usr/bin/env python3
"""Verifier for csv_batch_to_hl7_transformation task."""

import json
import tempfile
import os
import re

def verify_csv_batch_to_hl7_transformation(traj, env_info, task_info):
    """Verify that the CSV was ingested, split, and transformed to HL7 correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/csv_batch_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criteria 1: Channel Configuration (30 pts)
    config_ok = True
    if result.get("channel_found", False):
        if result.get("config_is_file_reader", False):
            score += 5
        else:
            feedback_parts.append("Source is not File Reader")
            config_ok = False
            
        if result.get("config_is_csv", False):
            score += 10
        else:
            feedback_parts.append("Data type is not Delimited Text/CSV")
            config_ok = False

        if result.get("config_is_batch", False):
            score += 15
            feedback_parts.append("Batch processing enabled correctly")
        else:
            feedback_parts.append("Batch processing NOT enabled (Critical for splitting)")
            config_ok = False
    else:
        feedback_parts.append("No channel found")
        config_ok = False

    # Criteria 2: Output Files Generated (30 pts)
    count = result.get("output_file_count", 0)
    expected_count = 5
    if count == expected_count:
        score += 30
        feedback_parts.append(f"Correct number of HL7 files generated ({count})")
    elif count > 0:
        score += 15
        feedback_parts.append(f"Generated {count} files (expected {expected_count})")
    else:
        feedback_parts.append("No output files generated")

    # Criteria 3: Data Transformation Verification (40 pts)
    # Check the content of the sample HL7 message
    sample_content = result.get("sample_hl7_content", "")
    data_score = 0
    if sample_content and count > 0:
        # Check MSH-9 (Message Type)
        if "ADT^A04" in sample_content:
            data_score += 5
            feedback_parts.append("Message type correct (ADT^A04)")
        
        # Check Date Formatting (YYYYMMDD) - should not have hyphens
        # PID-7 is DOB. Look for a date string like 19800115 or similar
        # Regex for YYYYMMDD
        if re.search(r'\|\d{8}\|', sample_content):
            data_score += 10
            feedback_parts.append("Date format correct (YYYYMMDD)")
        elif re.search(r'\|\d{4}-\d{2}-\d{2}\|', sample_content):
             feedback_parts.append("Date format incorrect (contains hyphens)")
        
        # Check Timestamp Formatting (YYYYMMDDHHMM)
        # PV1-44 is Visit Date
        if re.search(r'\|\d{12}\|', sample_content):
            data_score += 10
            feedback_parts.append("Timestamp format correct (YYYYMMDDHHMM)")

        # Check for presence of mapped data (e.g., 'CARDIO', 'Smith', etc.)
        # We don't know exactly which file we grabbed, but it should contain one of the rows
        # Row 1: Smith, John, CARDIO
        # Row 2: Doe, Jane, DERM
        # Just check if typical CSV data exists in HL7 format (e.g. |Smith^John|)
        if re.search(r'\|[A-Za-z]+\^[A-Za-z]+\|', sample_content):
            data_score += 15
            feedback_parts.append("Name mapping appears correct (XPN format)")
        else:
            feedback_parts.append("Name mapping verification failed")
            
    score += data_score

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }