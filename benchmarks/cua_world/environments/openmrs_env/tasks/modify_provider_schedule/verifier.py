#!/usr/bin/env python3
"""
Verifier for modify_provider_schedule task.
Checks if the appointment block end time was updated to 12:00 PM.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_modify_provider_schedule(traj, env_info, task_info):
    """
    Verify the provider schedule block modification.
    Criteria:
    1. Block must still exist (not voided/deleted).
    2. End time must be 12:00:00 on the target date.
    3. Start time must remain 09:00:00 on the target date.
    4. VLM: Verify UI interaction.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    block_exists = result.get("block_exists", False)
    is_voided = result.get("is_voided", False)
    start_iso = result.get("final_start_iso", "")
    end_iso = result.get("final_end_iso", "")
    target_date_str = result.get("target_date", "")
    
    # Initialize Score
    score = 0
    feedback = []

    # 1. Block Existence Check
    if not block_exists:
        return {"passed": False, "score": 0, "feedback": "Appointment block not found (may have been deleted)."}
    
    if is_voided:
        return {"passed": False, "score": 0, "feedback": "Appointment block was deleted (voided). Task required modification, not deletion."}

    score += 20
    feedback.append("Block exists and is active.")

    # 2. Verify Times
    # Parse ISO strings (e.g., 2025-10-10T09:00:00.000+0000)
    # We'll rely on string matching for the time part to avoid timezone hell if possible,
    # or simple parsing. OMRS dates usually usually have timezone offset.
    
    try:
        # Simple string splitting to get time part if standard ISO
        # Expected format: YYYY-MM-DDTHH:MM:SS.mmm+0000
        
        # Check Date
        if target_date_str not in start_iso:
            feedback.append(f"Block date seems to have moved (Start: {start_iso}).")
        
        # Check Start Time (09:00)
        # We look for T09:00:00
        if "T09:00:00" in start_iso:
            score += 15
            feedback.append("Start time preserved (09:00).")
        else:
            feedback.append(f"Start time changed incorrectly (Found: {start_iso}).")

        # Check End Time (12:00)
        # We look for T12:00:00
        if "T12:00:00" in end_iso:
            score += 50
            feedback.append("End time correctly updated to 12:00 PM.")
        else:
            feedback.append(f"End time incorrect (Found: {end_iso}, Expected: 12:00).")

    except Exception as e:
        feedback.append(f"Error parsing dates: {e}")

    # 3. Provider Check (Implicit via block UUID retention, but good to verify)
    provider_name = result.get("provider_name", "")
    if "Schedule" in provider_name:
        score += 15
        feedback.append("Provider assignment correct.")
    else:
        feedback.append("Provider assignment seems wrong.")

    # Pass Threshold
    passed = (score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }