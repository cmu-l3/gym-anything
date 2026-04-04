#!/usr/bin/env python3
"""
Verifier for save_modified_project task.

Verifies:
1. Output file exists at correct path (15 pts)
2. File has valid size (>500 bytes) (10 pts)
3. File was created during task window (10 pts)
4. File content differs from original (Anti-gaming) (15 pts)
5. Pitch value '3' found in file text (15 pts)
6. VLM/App state checks (35 pts)
"""

import json
import tempfile
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_save_modified_project(traj, env_info, task_info):
    """
    Verify that the user loaded the project, modified pitch, and saved it.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # Criterion 1: Output file exists (15 pts)
    if result.get('output_exists'):
        score += 15
        feedback_parts.append("Output file found")
    else:
        feedback_parts.append("Output file not found")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts),
            "details": {"reason": "File not saved to correct path"}
        }

    # Criterion 2: File size (10 pts)
    size = result.get('file_size', 0)
    if size > 500:
        score += 10
        feedback_parts.append(f"File size valid ({size} bytes)")
    else:
        feedback_parts.append(f"File too small ({size} bytes)")

    # Criterion 3: Created during task (10 pts)
    if result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp predates task")

    # Criterion 4: MD5 Different (15 pts)
    if result.get('md5_different_from_original'):
        score += 15
        feedback_parts.append("File content modified from original")
    else:
        feedback_parts.append("File is identical to sample (no changes saved)")

    # Criterion 5: Pitch value check (15 pts)
    if result.get('pitch_value_found'):
        score += 15
        feedback_parts.append("Pitch value '3' found in project data")
    else:
        feedback_parts.append("Pitch value '3' NOT found in project data")

    # Criterion 6: QBlade running (5 pts)
    if result.get('qblade_running'):
        score += 5
    
    # Criterion 7: VLM Proxy (30 pts)
    # If file exists, is modified, and has correct data, we infer interaction
    if result.get('output_exists') and result.get('md5_different_from_original') and result.get('pitch_value_found'):
        score += 30
        feedback_parts.append("Workflow validated by file evidence")
    elif result.get('output_exists'):
        score += 10
        feedback_parts.append("Partial workflow validation")

    # Final scoring
    passed = score >= 60 and result.get('output_exists') and result.get('md5_different_from_original')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }