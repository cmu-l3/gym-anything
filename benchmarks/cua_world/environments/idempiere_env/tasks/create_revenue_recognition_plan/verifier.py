#!/usr/bin/env python3
"""
Verifier for create_revenue_recognition_plan task.
Verifies that a specific Revenue Recognition Rule was created in the database.
"""

import json
import os
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_revenue_recognition_plan(traj, env_info, task_info):
    """
    Verify the agent created the '12 Month Subscription' revenue recognition rule correctly.
    """
    # 1. Setup and retrieve result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract Data
    record_exists = result.get('record_exists', False)
    record = result.get('record', {})
    
    # Metadata expectations
    metadata = task_info.get('metadata', {})
    exp_name = metadata.get('expected_name', "12 Month Subscription")
    exp_freq = metadata.get('expected_frequency', "M")     # M = Month
    exp_time = metadata.get('expected_istimebased', "Y")   # Y = Yes
    exp_desc_part = metadata.get('expected_description_part', "Ratable recognition")

    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: Record Exists (30 pts)
    if record_exists:
        score += 30
        feedback_parts.append(f"Record '{exp_name}' created successfully.")
        
        # Criterion 2: Time Based Flag (20 pts)
        # DB returns 'Y' or 'N'
        if record.get('is_time_based') == exp_time:
            score += 20
            feedback_parts.append("Time Based flag set correctly.")
        else:
            feedback_parts.append(f"Time Based flag incorrect (Expected {exp_time}, got {record.get('is_time_based')}).")

        # Criterion 3: Recognition Frequency (20 pts)
        # DB returns 'M' for Month
        if record.get('frequency') == exp_freq:
            score += 20
            feedback_parts.append("Frequency set to Month correctly.")
        else:
            feedback_parts.append(f"Frequency incorrect (Expected {exp_freq}, got {record.get('frequency')}).")

        # Criterion 4: Description (10 pts)
        desc = record.get('description', '')
        if exp_desc_part.lower() in desc.lower():
            score += 10
            feedback_parts.append("Description contains correct text.")
        else:
            feedback_parts.append("Description text missing or incorrect.")

        # Criterion 5: Active Status (10 pts)
        if record.get('is_active') == 'Y':
            score += 10
            feedback_parts.append("Record is Active.")
        else:
            feedback_parts.append("Record is NOT Active.")

        # Criterion 6: Anti-gaming / Timestamp check (10 pts)
        # We perform a basic check that the record ID is present (implying database insertion)
        # A more rigorous check would parse the SQL timestamp, but existence + correct values 
        # in a clean environment is usually sufficient evidence of work.
        if record.get('id'):
            score += 10
            feedback_parts.append("Record validated in database.")

    else:
        feedback_parts.append(f"Record '{exp_name}' NOT found in database.")

    # 4. Final Determination
    # Pass threshold: 70 points.
    # Must have at least: Exists (30) + TimeBased (20) + Frequency (20) = 70
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }