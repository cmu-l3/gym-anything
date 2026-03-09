#!/usr/bin/env python3
"""
Verifier for create_shift_schedule task.

SCORING CRITERIA:
1. Shift ID 'WKDAY9TO5' exists (25 pts)
2. Shift Name matches 'Weekday Daytime 9-5' (20 pts)
3. Start Time is '0900' (20 pts)
4. Length is '8.00' (15 pts)
5. Weekdays are exactly Mon-Fri (20 pts)

Pass Threshold: 65/100
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_shift_schedule(traj, env_info, task_info):
    """
    Verify that the shift schedule was created correctly in Vicidial.
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
    
    # 1. Verify Shift Existence (25 pts)
    if not result.get('shift_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Shift with ID 'WKDAY9TO5' was not found in the database."
        }
    
    score += 25
    feedback_parts.append("Shift ID 'WKDAY9TO5' created (+25)")
    
    data = result.get('shift_data', {})
    
    # 2. Verify Name (20 pts)
    # Flexible case-insensitive check, allowing for minor spacing differences
    expected_name = "Weekday Daytime 9-5"
    actual_name = data.get('name', '').strip()
    
    if actual_name.lower() == expected_name.lower():
        score += 20
        feedback_parts.append("Shift Name correct (+20)")
    elif "weekday" in actual_name.lower() and "9-5" in actual_name.lower():
        score += 10
        feedback_parts.append(f"Shift Name '{actual_name}' partially correct (+10)")
    else:
        feedback_parts.append(f"Shift Name mismatch: expected '{expected_name}', got '{actual_name}'")

    # 3. Verify Start Time (20 pts)
    # Vicidial stores as HHMM string usually
    actual_start = str(data.get('start_time', '')).strip()
    expected_start = "0900"
    
    # Handle cases like "900" or "09:00" flexibly
    normalized_start = actual_start.replace(':', '')
    if len(normalized_start) == 3: normalized_start = "0" + normalized_start
    
    if normalized_start == expected_start:
        score += 20
        feedback_parts.append("Start Time correct (+20)")
    else:
        feedback_parts.append(f"Start Time mismatch: expected '{expected_start}', got '{actual_start}'")

    # 4. Verify Length (15 pts)
    # Expect 8.00, allow 8 or 8.0
    actual_length_str = str(data.get('length', '')).strip()
    try:
        actual_length = float(actual_length_str)
        if 7.9 <= actual_length <= 8.1:
            score += 15
            feedback_parts.append("Shift Length correct (+15)")
        else:
            feedback_parts.append(f"Shift Length incorrect: expected 8.00, got {actual_length}")
    except ValueError:
        feedback_parts.append(f"Shift Length invalid format: {actual_length_str}")

    # 5. Verify Weekdays (20 pts)
    # Vicidial stores weekdays as a string (e.g. "1 2 3 4 5" or "1-2-3-4-5")
    # 0=Sunday, 1=Monday... 6=Saturday
    actual_weekdays = str(data.get('weekdays', ''))
    
    # Extract all digits
    days_found = re.findall(r'\d', actual_weekdays)
    
    has_weekdays = all(d in days_found for d in ['1', '2', '3', '4', '5'])
    has_weekend = any(d in days_found for d in ['0', '6'])
    
    if has_weekdays and not has_weekend:
        score += 20
        feedback_parts.append("Weekdays correct (Mon-Fri) (+20)")
    elif has_weekdays and has_weekend:
        score += 10
        feedback_parts.append("Weekdays include Mon-Fri but also include weekends (+10)")
    elif len(days_found) > 0:
        feedback_parts.append(f"Weekdays incorrect config: {actual_weekdays}")
    else:
        feedback_parts.append("No weekdays selected")

    # Anti-gaming check (Final Count > Initial Count)
    # This ensures they didn't just edit an existing row if we hadn't cleared it
    # (Though setup script clears it, this is a good sanity check)
    initial_count = result.get('initial_count', 0)
    final_count = result.get('final_count', 0)
    if final_count <= initial_count:
        feedback_parts.append("(Warning: Total shift count did not increase)")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }