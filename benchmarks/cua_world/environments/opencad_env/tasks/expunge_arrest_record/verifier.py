#!/usr/bin/env python3
"""Verifier for expunge_arrest_record task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_expunge_arrest_record(traj, env_info, task_info):
    """
    Verify that the agent deleted the specific arrest record while preserving data integrity.
    
    Criteria:
    1. Target arrest record (Elias Thorne) must be GONE (0).
    2. Target identity (Elias Thorne) must EXIST (>0).
    3. Distractor arrest (Sarah Connor) must EXIST (>0).
    4. Total arrest count should decrease by exactly 1.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/expunge_arrest_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    target_arrests = int(result.get('target_arrest_count', -1))
    target_identity = int(result.get('target_identity_count', -1))
    distractor_arrests = int(result.get('distractor_arrest_count', -1))
    
    initial_total = int(result.get('initial_arrest_count', 0))
    current_total = int(result.get('current_arrest_count', 0))
    
    # Criterion 1: Target Arrest Deleted (40 pts)
    if target_arrests == 0:
        score += 40
        feedback_parts.append("Target arrest record successfully expunged")
    else:
        feedback_parts.append(f"Target arrest record still exists (found {target_arrests})")
        
    # Criterion 2: Civilian Identity Preserved (30 pts)
    # The agent should NOT delete the person from ncic_names, only the arrest from arrests table
    if target_identity > 0:
        score += 30
        feedback_parts.append("Civilian identity profile preserved")
    else:
        feedback_parts.append("CRITICAL: Civilian identity was deleted along with the arrest")
        
    # Criterion 3: Distractor Data Preserved (20 pts)
    if distractor_arrests > 0:
        score += 20
        feedback_parts.append("Other arrest records preserved")
    else:
        feedback_parts.append("CRITICAL: Other arrest records were incorrectly deleted")
        
    # Criterion 4: Precision Check (10 pts)
    # Count should drop by exactly 1
    diff = initial_total - current_total
    if diff == 1:
        score += 10
        feedback_parts.append("Database record count changed by exactly -1")
    elif diff > 1:
        feedback_parts.append(f"Too many records deleted (count dropped by {diff})")
    elif diff == 0:
        feedback_parts.append("No records were deleted")
    else:
        feedback_parts.append(f"Record count increased (delta {diff})")

    # Pass threshold: 70 points
    # This ensures at least Target Deleted + Identity Preserved are met
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }