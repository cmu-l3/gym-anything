#!/usr/bin/env python3
"""
Verifier for configure_regional_system_settings task.
Verifies that OpenProject system settings match the required regional configuration.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_regional_system_settings(traj, env_info, task_info):
    """
    Verify that regional settings (timezone, start of week, date/time format) are correct.
    
    Criteria:
    1. Time Zone is 'Berlin'
    2. Start of Week is 'Monday' (1)
    3. Date Format is 'DD.MM.YYYY' (%d.%m.%Y)
    4. Time Format is 'HH:MM' (%H:%M)
    5. Settings were actually updated during the task (Anti-gaming)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values from metadata
    metadata = task_info.get('metadata', {})
    exp_tz = metadata.get('expected_time_zone', 'Berlin')
    exp_sow = metadata.get('expected_start_of_week', '1')
    exp_date = metadata.get('expected_date_format', '%d.%m.%Y')
    exp_time = metadata.get('expected_time_format', '%H:%M')

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    rails_data = result.get('rails_data', {})
    if rails_data.get('status') != 'success':
        return {"passed": False, "score": 0, "feedback": f"Internal error querying settings: {rails_data.get('message')}"}

    values = rails_data.get('values', {})
    timestamps = rails_data.get('timestamps', {})
    task_start = result.get('task_start', 0)

    score = 0
    feedback_parts = []
    
    # 1. Verify Time Zone (25 pts)
    # The value usually stored is 'Berlin' or 'Europe/Berlin'. OpenProject UI says 'Berlin'.
    actual_tz = str(values.get('time_zone', ''))
    if exp_tz in actual_tz:
        score += 25
        feedback_parts.append(f"Time zone correct ({actual_tz})")
    else:
        feedback_parts.append(f"Time zone incorrect: expected '{exp_tz}', got '{actual_tz}'")

    # 2. Verify Start of Week (25 pts)
    # '1' represents Monday in OpenProject
    actual_sow = str(values.get('start_of_week', ''))
    if actual_sow == exp_sow:
        score += 25
        feedback_parts.append("Start of week correct (Monday)")
    else:
        feedback_parts.append(f"Start of week incorrect: expected '{exp_sow}', got '{actual_sow}'")

    # 3. Verify Date Format (25 pts)
    actual_date = str(values.get('date_format', ''))
    if actual_date == exp_date:
        score += 25
        feedback_parts.append("Date format correct (DD.MM.YYYY)")
    else:
        feedback_parts.append(f"Date format incorrect: expected '{exp_date}', got '{actual_date}'")

    # 4. Verify Time Format (25 pts)
    actual_time = str(values.get('time_format', ''))
    if actual_time == exp_time:
        score += 25
        feedback_parts.append("Time format correct (HH:MM)")
    else:
        feedback_parts.append(f"Time format incorrect: expected '{exp_time}', got '{actual_time}'")

    # Anti-gaming check: Ensure at least one setting was updated *after* task start
    # We check timestamps.
    updated_during_task = False
    for key, ts in timestamps.items():
        if ts > task_start:
            updated_during_task = True
            break
    
    if not updated_during_task:
        feedback_parts.append("WARNING: No settings were modified during the task session.")
        # We penalize but don't fail completely if values are correct (rare edge case where setup failed to reset)
        # However, for a rigorous test, this should probably be a fail. 
        # Given the setup script resets them, they MUST change to be correct.
        # If they match but weren't updated, the reset failed or something is wrong.
        if score == 100:
             score = 50 # Significant penalty
             feedback_parts.append("Penalty: Database records do not show recent updates.")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }