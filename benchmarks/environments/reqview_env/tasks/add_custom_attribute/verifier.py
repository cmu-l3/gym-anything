#!/usr/bin/env python3
"""Verifier for add_custom_attribute task.

Checks that the agent added a 'Verification Method' custom attribute to the
project configuration with the correct type and enumeration values.

Verification criteria:
1. project.json has an 'attributes' array
2. An attribute with name='Verification Method' exists
3. Attribute type is enum/enumeration/list
4. Values include: Test, Inspection, Analysis, Demonstration
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PROJECT_PATH = "/home/ga/Documents/ReqView/add_custom_attr_project/project.json"


def verify_add_custom_attribute(traj, env_info, task_info):
    """Verify the custom attribute was added to the project configuration."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('attribute_name', 'Verification Method')
    expected_type = metadata.get('attribute_type', 'enum')
    expected_values = metadata.get('expected_values', ['Test', 'Inspection', 'Analysis', 'Demonstration'])

    # Copy project.json from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(PROJECT_PATH, tmp.name)
        with open(tmp.name) as f:
            proj = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read project.json: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []

    raw_attributes = proj.get('attributes', [])

    # Normalize: attributes may be a list or a dict (ReqView project.json uses dict with ID keys)
    if isinstance(raw_attributes, dict):
        attributes = list(raw_attributes.values())
    elif isinstance(raw_attributes, list):
        attributes = raw_attributes
    else:
        attributes = []

    # Check 1: attributes array exists with at least one entry (20 points)
    if not attributes:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No custom attributes found in project.json"
        }
    score += 20
    feedback_parts.append(f"{len(attributes)} attribute(s) in project")

    # Check 2: Attribute with expected name exists (30 points)
    match = None
    for attr in attributes:
        attr_name = attr.get('name', '') or attr.get('id', '') or attr.get('label', '')
        if expected_name.lower() in str(attr_name).lower():
            match = attr
            break

    if not match:
        existing = [a.get('name', a.get('id', '?')) for a in attributes]
        return {
            "passed": False,
            "score": score,
            "feedback": f"Attribute '{expected_name}' not found. Existing: {existing}"
        }
    score += 30
    feedback_parts.append(f"Attribute '{expected_name}' found")

    # Check 3: Type is enum/enumeration/list (25 points)
    attr_type = str(match.get('type', '')).lower()
    enum_synonyms = {'enum', 'enumeration', 'list', 'select', 'dropdown', 'choice'}
    if attr_type in enum_synonyms or expected_type.lower() in attr_type:
        score += 25
        feedback_parts.append(f"Type='{attr_type}' (enum) correct")
    else:
        feedback_parts.append(f"Type='{attr_type}' (expected enum/enumeration)")

    # Check 4: Values include required enumeration options (25 points)
    # Values may be in 'values', 'options', 'choices', 'items', or 'enum' key
    attr_values_raw = (
        match.get('values') or match.get('options') or
        match.get('choices') or match.get('items') or
        match.get('enum') or []
    )
    # Normalize: values may be list of strings or list of dicts with 'name'/'value' key
    def extract_val(v):
        if isinstance(v, str):
            return v
        if isinstance(v, dict):
            return v.get('name') or v.get('value') or v.get('label') or str(v)
        return str(v)

    attr_values = [extract_val(v).strip() for v in attr_values_raw]
    attr_values_lower = [v.lower() for v in attr_values]

    found_values = []
    missing_values = []
    for ev in expected_values:
        if ev.lower() in attr_values_lower:
            found_values.append(ev)
        else:
            missing_values.append(ev)

    if len(found_values) == len(expected_values):
        score += 25
        feedback_parts.append(f"All {len(expected_values)} enumeration values present")
    elif found_values:
        partial = int(25 * len(found_values) / len(expected_values))
        score += partial
        feedback_parts.append(
            f"Partial values: found {found_values}, missing {missing_values}"
        )
    else:
        feedback_parts.append(
            f"No expected values found. Attribute values: {attr_values}"
        )

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "attribute_found": match.get('name', match.get('id')),
            "attribute_type": attr_type,
            "attribute_values": attr_values,
            "found_required_values": found_values,
            "missing_required_values": missing_values,
        }
    }
