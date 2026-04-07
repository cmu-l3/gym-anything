#!/usr/bin/env python3
"""
Verifier for reorder_folder_contents task.

Verifies that the documents in the 'Onboarding Checklist' folder are arranged
in the correct order:
1. Step 1: Preparation
2. Step 2: Training
3. Step 3: Assessment
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reorder_folder_contents(traj, env_info, task_info):
    """
    Verify the order of documents in the Nuxeo folder.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected order of titles
    metadata = task_info.get('metadata', {})
    expected_order = metadata.get('expected_order', [
        "Step 1: Preparation",
        "Step 2: Training",
        "Step 3: Assessment"
    ])

    # Copy result file from container
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

    # Parse children from result
    children_response = result.get('folder_children', {})
    entries = children_response.get('entries', [])
    
    if not entries:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No documents found in the Onboarding Checklist folder."
        }

    # Extract titles in their current order
    actual_titles = [doc.get('title', 'Unknown') for doc in entries]
    
    score = 0
    feedback_lines = []
    
    # Check length
    if len(actual_titles) != 3:
        feedback_lines.append(f"Expected 3 documents, found {len(actual_titles)}.")
    
    # Check positions
    # Position 1
    if len(actual_titles) > 0:
        if actual_titles[0] == expected_order[0]:
            score += 40
            feedback_lines.append(f"✓ Position 1 correct: {actual_titles[0]}")
        else:
            feedback_lines.append(f"✗ Position 1 wrong: Found '{actual_titles[0]}', expected '{expected_order[0]}'")
            
    # Position 2
    if len(actual_titles) > 1:
        if actual_titles[1] == expected_order[1]:
            score += 30
            feedback_lines.append(f"✓ Position 2 correct: {actual_titles[1]}")
        else:
            feedback_lines.append(f"✗ Position 2 wrong: Found '{actual_titles[1]}', expected '{expected_order[1]}'")

    # Position 3
    if len(actual_titles) > 2:
        if actual_titles[2] == expected_order[2]:
            score += 30
            feedback_lines.append(f"✓ Position 3 correct: {actual_titles[2]}")
        else:
            feedback_lines.append(f"✗ Position 3 wrong: Found '{actual_titles[2]}', expected '{expected_order[2]}'")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }