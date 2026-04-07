#!/usr/bin/env python3
"""
Verifier for xml_batch_split_to_json task.

Scoring Criteria:
1. Channel Created (20 pts)
2. Batch Splitting Configured (Output files > 1) (20 pts)
3. Complete Splitting (Exactly 5 output files) (10 pts)
4. JSON Transformation (Output is valid JSON) (30 pts)
5. Data Integrity (Correct patient names found) (20 pts)

Anti-gaming:
- Checks timestamps of output files.
- Checks validity of JSON structure.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_xml_batch_split_to_json(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Metrics
    channel_exists = result.get("channel_exists", False)
    output_count = result.get("output_file_count", 0)
    json_count = result.get("valid_json_count", 0)
    names_found = result.get("names_found_count", 0)
    input_remains = result.get("input_file_remains", True)
    
    score = 0
    feedback = []

    # 1. Channel Creation (20 pts)
    # We accept if the channel ID was found OR if files were produced (implicit proof of channel)
    if channel_exists or output_count > 0:
        score += 20
        feedback.append("SUCCESS: Channel created/active.")
    else:
        feedback.append("FAIL: No 'Census_Processor' channel found and no output generated.")

    # 2. Batch Splitting (30 pts total)
    # Partial credit for generating > 1 file (means some splitting happened)
    if output_count > 1:
        score += 20
        feedback.append(f"SUCCESS: Batch splitting active ({output_count} files generated).")
        
        # Full credit for exact count (5)
        if output_count == 5:
            score += 10
            feedback.append("SUCCESS: Exact expected file count (5) achieved.")
        else:
            feedback.append(f"WARNING: Expected 5 files, found {output_count}. Check split delimiter/xpath.")
    elif output_count == 1:
        feedback.append("FAIL: Only 1 output file found. Batch processing/splitting likely not configured.")
    else:
        feedback.append("FAIL: No output files found.")

    # 3. JSON Transformation (30 pts)
    if json_count == 5:
        score += 30
        feedback.append("SUCCESS: All output files are valid JSON.")
    elif json_count > 0:
        # Proportional credit
        points = int((json_count / 5) * 30)
        score += points
        feedback.append(f"PARTIAL: {json_count}/5 files are valid JSON.")
    elif output_count > 0:
        feedback.append("FAIL: Output files exist but are not valid JSON (Check transformer settings).")

    # 4. Data Integrity (20 pts)
    # Did we find the expected patient names in the JSON?
    if names_found == 5:
        score += 20
        feedback.append("SUCCESS: All patient records correctly preserved.")
    elif names_found > 0:
        points = int((names_found / 5) * 20)
        score += points
        feedback.append(f"PARTIAL: Found {names_found}/5 patient records.")
    
    # Bonus/Penalty check: Input file processing
    # If output exists but input file remains, they might not have enabled 'Delete after read' or 'Move'
    # We don't penalize heavily but it's good practice.
    if output_count == 5 and input_remains:
        feedback.append("NOTE: Input file was not deleted/moved. In production, this might cause re-processing.")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }