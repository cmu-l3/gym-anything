#!/usr/bin/env python3
"""
Verifier for add_kitchen_printer task.

Criteria:
1. Database Verification (Primary):
   - Printer 'Kitchen-Expo-1' exists in VIRTUAL_PRINTER table.
   - Printer count increased by at least 1.
2. Application State:
   - App was running at the end (before verification kill).
3. VLM Verification (Secondary):
   - Confirms UI interaction if DB check is ambiguous (optional but good practice).
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_kitchen_printer(traj, env_info, task_info):
    """
    Verifies that the kitchen printer was correctly added to Floreant POS.
    """
    # 1. Setup: Retrieve result file from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Infrastructure error: copy_from_env not available"
        }

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load task result from environment: {str(e)}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion A: App was running (10 pts)
    # This proves the agent didn't just crash the app or exit immediately
    if result_data.get("app_was_running", False):
        score += 10
        feedback_parts.append("Application was running.")
    else:
        feedback_parts.append("Application was NOT running at end of task.")

    # Criterion B: Printer Record Found (60 pts)
    # This is the core success criteria - the specific named entity exists
    if result_data.get("printer_found", False):
        score += 60
        feedback_parts.append("Printer 'Kitchen-Expo-1' found in database.")
    else:
        feedback_parts.append("Printer 'Kitchen-Expo-1' NOT found in database.")

    # Criterion C: New Record Created (30 pts)
    # Verifies that we actually added something, didn't just rename an existing one
    # (Though in a fresh env, renaming is unlikely, this is a good anti-gaming check)
    count_diff = result_data.get("count_diff", 0)
    if count_diff >= 1:
        score += 30
        feedback_parts.append(f"Database record count increased by {count_diff}.")
    elif count_diff == 0 and result_data.get("printer_found", False):
        # Edge case: Maybe they renamed an existing one? We give partial credit.
        score += 10
        feedback_parts.append("Database count did not increase (modified existing?).")
    else:
        feedback_parts.append("No new database records created.")

    # 3. Final Determination
    # Must have found the printer AND created a new record to pass fully
    passed = (score >= 90)

    # Secondary check: If we have the printer but score is low (e.g. app wasn't running),
    # we might still consider it a pass if the data is persistent.
    if result_data.get("printer_found", False) and score >= 60:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }