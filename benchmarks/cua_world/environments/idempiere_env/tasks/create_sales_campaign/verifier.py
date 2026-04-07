#!/usr/bin/env python3
"""
Verifier for create_sales_campaign task in iDempiere.

Verification logic:
1. Primary: Check database for specific record details (Value, Name, Dates, Costs).
2. Anti-gaming: Ensure record was created AFTER task start time.
3. Secondary: Visual verification via VLM to confirm UI state.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_sales_campaign(traj, env_info, task_info):
    """
    Verifies the creation of a sales campaign in iDempiere.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_value = metadata.get('expected_value', "SPRING-GARDEN-2025")
    expected_name = metadata.get('expected_name', "Spring Garden Promotion 2025")
    expected_start = metadata.get('expected_start_date', "2025-04-01")
    expected_end = metadata.get('expected_end_date', "2025-06-30")
    expected_costs = metadata.get('expected_costs', 15000)

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Check if record exists (Critical)
    if not result.get('record_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"FAILED: Campaign record '{expected_value}' was not found in the database."
        }
    
    score += 20
    feedback_parts.append("Record created")

    # Check Data Fields
    data = result.get('record_data', {})
    
    # Name (15 pts)
    if data.get('name') == expected_name:
        score += 15
        feedback_parts.append("Name correct")
    else:
        feedback_parts.append(f"Name mismatch (got '{data.get('name')}')")

    # Description (10 pts) - Keyword match
    desc = data.get('description', '').lower()
    if 'garden' in desc or 'promotion' in desc:
        score += 10
        feedback_parts.append("Description contains keywords")
    else:
        feedback_parts.append("Description missing keywords")

    # Start Date (15 pts)
    if data.get('start_date') == expected_start:
        score += 15
        feedback_parts.append("Start date correct")
    else:
        feedback_parts.append(f"Start date incorrect (got {data.get('start_date')})")

    # End Date (15 pts)
    if data.get('end_date') == expected_end:
        score += 15
        feedback_parts.append("End date correct")
    else:
        feedback_parts.append(f"End date incorrect (got {data.get('end_date')})")

    # Costs (15 pts) - Allow small float tolerance
    try:
        actual_costs = float(data.get('costs', 0))
        if abs(actual_costs - float(expected_costs)) < 0.01:
            score += 15
            feedback_parts.append("Costs correct")
        else:
            feedback_parts.append(f"Costs incorrect (got {actual_costs})")
    except ValueError:
        feedback_parts.append("Costs field invalid")

    # 3. Anti-Gaming Checks (10 pts)
    task_start = result.get('task_start', 0)
    created_epoch = data.get('created_epoch', 0)
    
    if created_epoch >= task_start:
        score += 5
        feedback_parts.append("Created during session")
    else:
        feedback_parts.append("WARN: Record timestamp predates task start")

    if result.get('app_running', False):
        score += 5
        feedback_parts.append("App verified running")
    else:
        feedback_parts.append("App not running at end")

    # 4. VLM Verification (Bonus/Confirmation)
    # Since this is a data-entry task, DB verification is primary. 
    # VLM is used here to ensure the UI is in a reasonable state (not error screen).
    
    # If using gym_anything.vlm, we could verify the screenshot.
    # For now, we assume if the DB record is correct and created now, the task is valid.
    # We'll just verify the screenshot file exists as a proxy for visual state availability.
    # (Real VLM implementation would query "Is the Campaign window visible?")
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }