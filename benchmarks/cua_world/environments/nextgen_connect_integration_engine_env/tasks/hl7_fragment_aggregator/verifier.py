#!/usr/bin/env python3
"""
Verifier for HL7 Fragment Aggregator task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hl7_fragment_aggregator(traj, env_info, task_info):
    """
    Verify that the agent correctly aggregated 3 HL7 fragments into 1 message.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
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
    channel_exists = result.get('channel_exists', False)
    file_count = result.get('output_file_count', 0)
    obx_count = result.get('obx_segment_count', 0)
    created_during_task = result.get('file_created_during_task', False)
    
    score = 0
    feedback_parts = []

    # Criterion 1: Channel Creation (20 pts)
    if channel_exists:
        score += 20
        feedback_parts.append("Aggregator channel created.")
    else:
        feedback_parts.append("No channel found with 'Aggregator' or 'Lipid' in name.")

    # Criterion 2: Output Generation (20 pts)
    if file_count > 0 and created_during_task:
        score += 20
        feedback_parts.append(f"Output file generated ({file_count} file(s)).")
    elif file_count > 0:
        feedback_parts.append("Output file exists but has old timestamp.")
    else:
        feedback_parts.append("No output file generated.")

    # Criterion 3: Aggregation Logic (Single File) (20 pts)
    # Ideally, we want EXACTLY 1 file for the 3 inputs.
    if file_count == 1:
        score += 20
        feedback_parts.append("Correctly produced exactly one output file.")
    elif file_count > 1:
        score += 5
        feedback_parts.append(f"Produced {file_count} output files (expected 1 consolidated file).")

    # Criterion 4: Content Verification (Correct Merge) (40 pts)
    # We expect 3 OBX segments in the final file (Cholesterol, HDL, LDL)
    if obx_count == 3:
        score += 40
        feedback_parts.append("Output file contains all 3 OBX segments.")
    elif obx_count > 0:
        score += 10
        feedback_parts.append(f"Output file contains {obx_count} OBX segments (expected 3). Partial aggregation or passthrough.")
    else:
        feedback_parts.append("Output file contains no OBX segments.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }