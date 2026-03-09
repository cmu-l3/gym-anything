#!/usr/bin/env python3
"""
Verifier for tracker_search_view_config task.

Scoring (100 points total):
- Child Programme modified (20 pts)
- Gender/Sex attribute visible in list (40 pts)
- Address/Village attribute visible in list (40 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_tracker_search_view_config(traj, env_info, task_info):
    """Verify that the Child Programme search view was configured correctly."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/tracker_search_view_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        score = 0
        feedback_parts = []
        subscores = {}

        # Check if program was found
        found_program = result.get('found_program', False)
        details = result.get('program_details') or {}
        
        if not found_program:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not find 'Child Programme' in DHIS2 configuration.",
                "subscores": {"program_found": False}
            }

        program_name = details.get('program_name', 'Unknown Program')
        feedback_parts.append(f"Checked program: '{program_name}'")

        # Criterion 1: Program modified (implied if we find the changes, but let's give points for finding it)
        # We'll award these points if at least one attribute is correct, showing they found the right place
        gender_visible = details.get('gender_visible', False)
        address_visible = details.get('address_visible', False)
        
        if gender_visible or address_visible:
            score += 20
            subscores["program_modified"] = True
            feedback_parts.append("Program configuration accessed (+20)")
        else:
            subscores["program_modified"] = False
            feedback_parts.append("No changes detected to target attributes")

        # Criterion 2: Gender visible
        if gender_visible:
            score += 40
            subscores["gender_visible"] = True
            attr_name = details.get('gender_attr_name', 'Gender')
            feedback_parts.append(f"Attribute '{attr_name}' is set to display in list (+40)")
        else:
            subscores["gender_visible"] = False
            feedback_parts.append("Gender/Sex attribute NOT set to display in list")

        # Criterion 3: Address visible
        if address_visible:
            score += 40
            subscores["address_visible"] = True
            attr_name = details.get('address_attr_name', 'Address')
            feedback_parts.append(f"Attribute '{attr_name}' is set to display in list (+40)")
        else:
            subscores["address_visible"] = False
            feedback_parts.append("Address/Village attribute NOT set to display in list")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}