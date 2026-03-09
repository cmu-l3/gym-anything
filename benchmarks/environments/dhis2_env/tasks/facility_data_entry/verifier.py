#!/usr/bin/env python3
"""
Verifier for facility_data_entry task.

Scoring (100 points total):
- Data exists for Ngelehun CHC / Jan 2024 (25 pts) [MANDATORY]
- At least 5 data values recorded (20 pts)
- Data values match expected targets (20 pts)
- Data was entered/updated AFTER task start (15 pts)
- Form marked as Complete (20 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_facility_data_entry(traj, env_info, task_info):
    """Verify aggregate data entry for facility."""
    
    # 1. Setup and load result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        copy_from_env("/tmp/facility_data_entry_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # 2. Extract Data
    task_start_ts = float(result.get('task_start_timestamp', 0))
    data_values = result.get('data_values', [])
    is_completed = result.get('is_completed', False)
    
    score = 0
    feedback_parts = []
    
    # Define expected values (approximate matching for data element names)
    expected_map = {
        "BCG": 47,
        "OPV 1": 38,
        "OPV 3": 32,
        "Penta 1": 40,
        "Penta 3": 35,
        "Measles": 28,
        "Yellow Fever": 25,
        "Fully immunized": 22
    }
    
    # 3. Verify Data Existence (Mandatory)
    if not data_values:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No data values found for Ngelehun CHC in Jan 2024. Agent must enter data and save."
        }
    
    score += 25
    feedback_parts.append(f"Data values found ({len(data_values)}) (+25)")
    
    # 4. Verify Quantity of Data
    if len(data_values) >= 5:
        score += 20
        feedback_parts.append("≥5 data values entered (+20)")
    else:
        feedback_parts.append(f"Only {len(data_values)} values entered (target: 8)")
        
    # 5. Verify Timing (Anti-Gaming)
    # Check if any data value has lastupdated > task_start
    # Since we cleared data in setup, existence implies new creation, 
    # but we check timestamp to be sure the DB clock isn't wild or old data wasn't missed.
    # Note: DHIS2 DB timestamps might be string formatted.
    
    def parse_db_time(t_str):
        # Format usually: 2023-10-25 10:00:00 or similar
        try:
            # Handle potential millisecond formats or T separators
            cleaned = t_str.replace('T', ' ').split('.')[0]
            dt = datetime.strptime(cleaned, "%Y-%m-%d %H:%M:%S")
            return dt.timestamp()
        except:
            return 0

    new_data_count = 0
    for dv in data_values:
        ts = parse_db_time(dv.get('lastupdated', ''))
        # Allow small clock skew (e.g. 5 seconds)
        if ts >= (task_start_ts - 5):
            new_data_count += 1
            
    if new_data_count > 0:
        score += 15
        feedback_parts.append("Data entry timestamps confirmed valid (+15)")
    else:
        feedback_parts.append("Warning: Data timestamps appear older than task start (possibly pre-existing?)")
        
    # 6. Verify Value Accuracy
    matches = 0
    
    for key, val in expected_map.items():
        # Find corresponding data element
        found = False
        for dv in data_values:
            de_name = dv.get('data_element', '').lower()
            dv_val = dv.get('value', '')
            
            # Simple fuzzy match: if expected key word is in DE name
            # e.g. "BCG" in "BCG doses given"
            if key.lower() in de_name:
                try:
                    if float(dv_val) == float(val):
                        found = True
                        break
                except ValueError:
                    pass
        if found:
            matches += 1
            
    if matches >= 5:
        score += 20
        feedback_parts.append(f"≥5 values match expected numbers ({matches}/8) (+20)")
    elif matches > 0:
        score += 10
        feedback_parts.append(f"Some values match expected numbers ({matches}/8) (+10)")
    else:
        feedback_parts.append("No values matched expected numbers")

    # 7. Verify Completion
    if is_completed:
        score += 20
        feedback_parts.append("Form marked as complete (+20)")
    else:
        feedback_parts.append("Form NOT marked as complete")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }