#!/usr/bin/env python3
"""
Verifier for configure_provider_schedule_slots task.
Checks if the provider's schedule increment was updated in the database.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_provider_schedule_slots(traj, env_info, task_info):
    """
    Verify that the schedule increment for demo_provider is 15.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_increment = str(metadata.get('expected_increment', 15))
    initial_increment = str(metadata.get('initial_increment', 20))

    # Read result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract values
    final_val = str(result.get("final_increment", "ERROR")).strip()
    initial_val = str(result.get("initial_increment", "0")).strip()
    
    score = 0
    feedback_parts = []
    
    # CRITERION 1: Value Check (60 points)
    if final_val == expected_increment:
        score += 60
        feedback_parts.append(f"Correct schedule increment set ({final_val} mins)")
    elif final_val == initial_val:
        feedback_parts.append(f"Value unchanged ({final_val} mins)")
    else:
        feedback_parts.append(f"Incorrect value: set to {final_val} mins, expected {expected_increment} mins")

    # CRITERION 2: Change Detection (20 points)
    # Ensure it's not just a coincidence (though setup resets it, this confirms action)
    if final_val != initial_val:
        score += 20
        feedback_parts.append("Configuration change detected")
    else:
        feedback_parts.append("No configuration change detected")

    # CRITERION 3: Target Verification (20 points)
    # Check if admin (id=1) was accidentally modified instead if possible, 
    # but here we just check if we hit the pass threshold.
    # In the export script, we check DB specifically for demo_provider.
    # If final_val is correct for demo_provider, we award these points assuming 
    # the agent navigated correctly.
    
    # We can use the admin_increment from result to ensure safety
    admin_val = str(result.get("admin_increment", "0")).strip()
    # Assuming admin shouldn't change to 15 (it might be NULL or default)
    # This is a soft check.
    if admin_val != expected_increment: 
        score += 20
        feedback_parts.append("Correct provider targeted")
    else:
        # If admin also has 15, agent might have changed global default or wrong user
        # But if they changed the specific user correctly too, we still give some credit
        # unless strictness is required.
        score += 10
        feedback_parts.append("Warning: Admin profile might have been modified too")

    passed = (final_val == expected_increment)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }