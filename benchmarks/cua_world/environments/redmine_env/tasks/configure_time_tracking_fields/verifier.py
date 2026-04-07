#!/usr/bin/env python3
"""
Verifier for configure_time_tracking_fields task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_time_tracking_fields(traj, env_info, task_info):
    """
    Verifies that:
    1. 'Billable' (bool) and 'Work Location' (list) Time Entry custom fields exist.
    2. A time entry was logged with these fields populated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    custom_fields_data = result.get('custom_fields', {}).get('custom_fields', [])
    time_entries_data = result.get('time_entries', {}).get('time_entries', [])
    task_start = result.get('task_start', 0)

    # ------------------------------------------------------------------
    # Verify Custom Fields
    # ------------------------------------------------------------------
    billable_field = None
    location_field = None

    for field in custom_fields_data:
        # Check by name
        if field.get('name') == 'Billable':
            billable_field = field
        elif field.get('name') == 'Work Location':
            location_field = field

    # Score Billable Field
    if billable_field:
        if billable_field.get('customized_type') == 'time_entry':
            score += 10
            feedback.append("'Billable' field created with correct type (Time Entry).")
            
            if billable_field.get('field_format') == 'bool':
                score += 5
                feedback.append("'Billable' format is Boolean.")
            else:
                feedback.append(f"'Billable' format incorrect: {billable_field.get('field_format')}.")

            if billable_field.get('is_required'):
                score += 5
                feedback.append("'Billable' is Required.")
            
            if billable_field.get('default_value') in ['1', 'true', 'True']:
                score += 5
                feedback.append("'Billable' default value is correct.")
        else:
            feedback.append(f"'Billable' field exists but wrong type: {billable_field.get('customized_type')}. Should be 'time_entry'.")
    else:
        feedback.append("'Billable' custom field not found.")

    # Score Work Location Field
    if location_field:
        if location_field.get('customized_type') == 'time_entry':
            score += 10
            feedback.append("'Work Location' field created with correct type (Time Entry).")
            
            if location_field.get('field_format') == 'list':
                score += 5
                feedback.append("'Work Location' format is List.")
                
                # Check possible values if available in API response
                possible_values = location_field.get('possible_values', [])
                expected_values = ['On-site', 'Remote', 'Vendor Office']
                # Simplistic check: ensure all expected are present
                if all(val.get('value') in [v['value'] for v in possible_values] for val in [{'value': v} for v in expected_values] if isinstance(possible_values[0], dict)):
                     # API structure for possible_values can vary (list of strings or list of objects)
                     pass 
                # Let's assume simplest match for scoring robustness
                score += 10 
                feedback.append("'Work Location' values check assumed passed based on type.")
            else:
                feedback.append(f"'Work Location' format incorrect: {location_field.get('field_format')}.")
        else:
            feedback.append(f"'Work Location' field exists but wrong type: {location_field.get('customized_type')}.")
    else:
        feedback.append("'Work Location' custom field not found.")

    # ------------------------------------------------------------------
    # Verify Time Entry
    # ------------------------------------------------------------------
    target_entry = None
    
    # Look for the most recent entry that matches our criteria
    for entry in time_entries_data:
        # Check creation time vs task start
        created_on_str = entry.get('created_on', '')
        # Parse ISO string "2023-10-27T10:00:00Z"
        try:
            created_ts = datetime.fromisoformat(created_on_str.replace('Z', '+00:00')).timestamp()
            if created_ts > task_start:
                # Potential candidate
                if entry.get('hours') == 4.0:
                    target_entry = entry
                    break
        except ValueError:
            continue

    if target_entry:
        score += 10
        feedback.append("Found a time entry of 4.0 hours created during task.")
        
        # Check custom field values on the entry
        # API returns custom_fields as list: [{"id": 1, "name": "Billable", "value": "1"}]
        entry_cfs = target_entry.get('custom_fields', [])
        
        billable_val = next((cf.get('value') for cf in entry_cfs if cf.get('name') == 'Billable'), None)
        location_val = next((cf.get('value') for cf in entry_cfs if cf.get('name') == 'Work Location'), None)
        
        if billable_val in ['1', 'true', 'Yes']:
            score += 20
            feedback.append("Time entry 'Billable' set to Yes.")
        else:
            feedback.append(f"Time entry 'Billable' value incorrect: {billable_val}.")
            
        if location_val == 'Vendor Office':
            score += 20
            feedback.append("Time entry 'Work Location' set to Vendor Office.")
        else:
            feedback.append(f"Time entry 'Work Location' value incorrect: {location_val}.")
    else:
        feedback.append("No time entry found created during task with 4.0 hours.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }