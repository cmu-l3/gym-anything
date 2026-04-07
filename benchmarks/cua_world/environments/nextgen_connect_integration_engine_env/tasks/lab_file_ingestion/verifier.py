#!/usr/bin/env python3
"""
Verifier for lab_file_ingestion task.

Checklist:
1. Channel exists and is named correctly.
2. Source is File Reader, Dest is File Writer.
3. Directories created correctly in container.
4. Channel is deployed (STARTED).
5. Output file exists and contains transformation (MSH-5 = LAB_REPOSITORY).
6. Source file was moved to processed directory.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lab_file_ingestion(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Channel Configuration (40 points)
    if result.get('channel_found', False):
        score += 10
        feedback.append(f"Channel found: {result.get('channel_name')}")
        
        if "Lab_Result_File_Ingestion" in result.get('channel_name', ''):
            score += 5
            feedback.append("Channel name matches exactly.")
    else:
        feedback.append("No channel found.")

    if result.get('source_type') == 'FileReader':
        score += 10
        feedback.append("Source connector is File Reader.")
    else:
        feedback.append(f"Incorrect source type: {result.get('source_type')}")

    if result.get('dest_type') == 'FileWriter':
        score += 10
        feedback.append("Destination connector is File Writer.")
    else:
        feedback.append(f"Incorrect destination type: {result.get('dest_type')}")
        
    if result.get('transformer_match', False):
        score += 5
        feedback.append("Transformer config looks correct (LAB_REPOSITORY found).")

    # 2. Environment Setup (Directory Creation) (15 points)
    dirs_score = 0
    if result.get('dir_input_exists', False): dirs_score += 5
    if result.get('dir_output_exists', False): dirs_score += 5
    if result.get('dir_processed_exists', False): dirs_score += 5
    score += dirs_score
    if dirs_score == 15:
        feedback.append("All required directories created successfully.")
    else:
        feedback.append(f"Directory setup incomplete (Score: {dirs_score}/15).")

    # 3. Deployment Status (10 points)
    status = result.get('channel_status', 'UNKNOWN')
    if status in ['STARTED', 'DEPLOYED', 'POLLING']:
        score += 10
        feedback.append(f"Channel is deployed and running ({status}).")
    else:
        feedback.append(f"Channel is not running (Status: {status}).")

    # 4. Functional Verification (35 points)
    # Output file creation
    output_count = result.get('output_file_count', 0)
    if output_count > 0:
        score += 15
        feedback.append("Output file created successfully.")
        
        # Check content transformation
        content = result.get('output_content_sample', '')
        if 'LAB_REPOSITORY' in content:
            score += 15
            feedback.append("Transformation verified: MSH-5 contains 'LAB_REPOSITORY'.")
        else:
            feedback.append("Transformation failed: 'LAB_REPOSITORY' not found in output.")
            logger.info(f"Actual content start: {content[:100]}")
    else:
        feedback.append("No output file generated.")

    # Processed file move
    processed_count = result.get('processed_file_count', 0)
    if processed_count > 0:
        score += 5
        feedback.append("Source file correctly moved to processed directory.")
    else:
        feedback.append("Source file was not moved to processed directory.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }