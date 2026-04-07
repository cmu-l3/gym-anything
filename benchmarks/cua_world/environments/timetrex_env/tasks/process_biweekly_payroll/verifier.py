#!/usr/bin/env python3
"""
Verifier for Process Bi-Weekly Payroll task in TimeTrex.

Uses copy_from_env to safely extract the exported JSON result.
Verifies task using multiple independent database signals:
1. Pay stub row count strictly increased (proves the payroll calculation engine ran).
2. A pay period was marked 'Processed' specifically matching the "Bi-Weekly" schedule.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_biweekly_payroll(traj, env_info, task_info):
    """
    Verify that the Bi-Weekly payroll was successfully processed.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available. Framework error."}

    # Extract expected metadata values
    metadata = task_info.get('metadata', {})
    expected_schedule = metadata.get('expected_schedule_name', 'Bi-Weekly')
    
    try:
        # Securely copy result JSON from the agent container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/payroll_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
                
        if "error" in result:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Export error: {result['error']}"
            }

        initial_count = int(result.get('initial_stub_count', 0))
        current_count = int(result.get('current_stub_count', 0))
        processed_schedule = result.get('processed_schedule', '')

        score = 0
        feedback_parts = []
        
        logger.info(f"Pay stubs: initial={initial_count}, current={current_count}")
        logger.info(f"Processed schedule: {processed_schedule}")

        # Criterion 1: Did the pay stub count increase? (50 points)
        # This proves the payroll processing engine actually executed and generated payslips
        stubs_generated = current_count - initial_count
        if stubs_generated > 0:
            score += 50
            feedback_parts.append(f"Payroll engine executed ({stubs_generated} pay stubs generated) [50/50]")
        else:
            feedback_parts.append("No new pay stubs generated (payroll engine was not executed) [0/50]")

        # Criterion 2: Did they process the correct schedule type? (50 points)
        # Prevents gaming by just processing ANY open pay period (like a Weekly one)
        if expected_schedule.lower() in processed_schedule.lower():
            score += 50
            feedback_parts.append(f"Correct pay period schedule processed: '{processed_schedule}' [50/50]")
        elif processed_schedule == "None":
            feedback_parts.append("No pay period was processed during the task timeframe [0/50]")
        else:
            # They processed something, but it was the wrong schedule (e.g., Weekly)
            feedback_parts.append(f"Wrong schedule processed. Expected '{expected_schedule}', got '{processed_schedule}' [0/50]")

        # Success determination
        passed = score == 100
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found in container - export_result.sh likely failed."
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result JSON is invalid: {e}"
        }
    except Exception as e:
        logger.error(f"Unexpected verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Unexpected error during verification: {e}"
        }