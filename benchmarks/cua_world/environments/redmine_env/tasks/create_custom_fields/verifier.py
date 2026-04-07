#!/usr/bin/env python3
"""
Verifier for create_custom_fields task (Redmine).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_fields(traj, env_info, task_info):
    """
    Verify that the three custom fields were created with correct settings.
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

    # Basic Checks
    if not result.get('app_was_running', False):
        return {"passed": False, "score": 0, "feedback": "Firefox was not running at end of task"}

    api_data = result.get('custom_fields_data', {})
    custom_fields = api_data.get('custom_fields', [])
    
    # Filter for issue custom fields
    issue_fields = [f for f in custom_fields if f.get('customized_type') == 'issue']

    score = 0
    max_score = 100
    feedback_parts = []

    # Helper to find field by name
    def find_field(name):
        for f in issue_fields:
            if f.get('name') == name:
                return f
        return None

    # Helper to check trackers
    # The API returns trackers as a list of dicts: [{"id": 1, "name": "Bug"}, ...]
    def check_trackers(field, expected_names):
        actual_trackers = field.get('trackers', [])
        actual_names = sorted([t.get('name') for t in actual_trackers])
        expected_sorted = sorted(expected_names)
        return actual_names == expected_sorted, actual_names

    # --- Field 1: Estimated Cost ---
    # Points: 32
    f1 = find_field("Estimated Cost")
    if f1:
        score += 8  # Existence
        feedback_parts.append("'Estimated Cost' created")
        
        # Format
        if f1.get('field_format') == 'float':
            score += 8
        else:
            feedback_parts.append(f"Estimated Cost: wrong format ({f1.get('field_format')})")

        # Trackers (Bug, Feature)
        ok, actual = check_trackers(f1, ["Bug", "Feature"])
        if ok:
            score += 8
        else:
            feedback_parts.append(f"Estimated Cost: wrong trackers {actual}")

        # Required
        if f1.get('is_required') is True:
            score += 5
        else:
            feedback_parts.append("Estimated Cost: not required")

        # Searchable (is_filter)
        if f1.get('is_filter') is True:
            score += 3
        else:
            feedback_parts.append("Estimated Cost: not searchable")
    else:
        feedback_parts.append("'Estimated Cost' missing")

    # --- Field 2: Building Wing ---
    # Points: 38
    f2 = find_field("Building Wing")
    if f2:
        score += 8
        feedback_parts.append("'Building Wing' created")

        # Format
        if f2.get('field_format') == 'list':
            score += 5
        else:
            feedback_parts.append(f"Building Wing: wrong format ({f2.get('field_format')})")

        # Possible Values
        # API returns list of dicts: [{"value": "X"}, ...] or simple list depending on version
        # Redmine JSON API usually returns 'possible_values': [{'value': 'A'}, {'value': 'B'}]
        p_values_raw = f2.get('possible_values', [])
        # Handle both list of dicts and list of strings just in case
        if p_values_raw and isinstance(p_values_raw[0], dict):
            p_values = [v.get('value') for v in p_values_raw]
        else:
            p_values = p_values_raw

        expected_values = ["North Wing", "South Wing", "East Wing", "West Wing", "Central Atrium"]
        
        # Exact match (order usually matters in Redmine lists but let's be lenient on order if contents match, 
        # though task asked for order)
        if p_values == expected_values:
            score += 12
        elif sorted(p_values) == sorted(expected_values):
            score += 6
            feedback_parts.append("Building Wing: values correct but wrong order")
        else:
            # Partial credit for overlap
            overlap = set(p_values).intersection(set(expected_values))
            partial = int(len(overlap) * 2)
            score += partial
            feedback_parts.append(f"Building Wing: wrong values (found {len(overlap)}/5)")

        # Trackers (All 3)
        ok, actual = check_trackers(f2, ["Bug", "Feature", "Support"])
        if ok:
            score += 10
        else:
            feedback_parts.append(f"Building Wing: wrong trackers {actual}")

        # Multiple (Should be false)
        if f2.get('multiple', False) is False:
            score += 3
        else:
            feedback_parts.append("Building Wing: incorrectly set to multiple")
    else:
        feedback_parts.append("'Building Wing' missing")

    # --- Field 3: Safety Inspection Required ---
    # Points: 30
    f3 = find_field("Safety Inspection Required")
    if f3:
        score += 8
        feedback_parts.append("'Safety Inspection Required' created")

        # Format
        if f3.get('field_format') == 'bool':
            score += 5
        else:
            feedback_parts.append(f"Safety Inspection: wrong format ({f3.get('field_format')})")

        # Default Value
        # Boolean default '1' is usually returned as "1" or true
        default_val = str(f3.get('default_value', '')).lower()
        if default_val in ['1', 'true', 'yes']:
            score += 7
        else:
            feedback_parts.append(f"Safety Inspection: wrong default ({default_val})")

        # Trackers (Bug, Support)
        ok, actual = check_trackers(f3, ["Bug", "Support"])
        if ok:
            score += 10
        else:
            feedback_parts.append(f"Safety Inspection: wrong trackers {actual}")
    else:
        feedback_parts.append("'Safety Inspection Required' missing")

    # Final check
    passed = (score >= 60) and (f1 is not None) and (f2 is not None) and (f3 is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }