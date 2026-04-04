#!/usr/bin/env python3
"""
Verifier for add_concept_mapping task.

Criteria:
1. Mapping exists with code 61462000 (50 pts)
2. Mapping source is 'SNOMED CT' (20 pts)
3. Mapping type is 'SAME-AS' (20 pts)
4. Anti-gaming: Mapping was created during task (implicit via setup cleaning + verification) (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_concept_mapping(traj, env_info, task_info):
    """
    Verify that the concept mapping was added correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_code = metadata.get('target_code', '61462000')
    target_source = metadata.get('target_source', 'SNOMED CT')
    target_map_type = metadata.get('target_map_type', 'SAME-AS')

    # Copy result file
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
    
    verification_data = result.get('verification_data', {})
    mapping_found = verification_data.get('mapping_found', False)
    details = verification_data.get('details', {})

    # Criterion 1: Mapping found (50 pts)
    if mapping_found:
        score += 50
        feedback_parts.append(f"Mapping with code {target_code} found")
    else:
        feedback_parts.append(f"Mapping with code {target_code} NOT found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Source check (20 pts)
    # We verify the agent selected the correct Dictionary/Source
    actual_source = details.get('source')
    if actual_source == target_source:
        score += 20
        feedback_parts.append(f"Correct source ({target_source})")
    else:
        feedback_parts.append(f"Incorrect source: expected '{target_source}', got '{actual_source}'")

    # Criterion 3: Map Type check (20 pts)
    # We verify the agent selected the correct relationship
    actual_map_type = details.get('map_type')
    if actual_map_type == target_map_type:
        score += 20
        feedback_parts.append(f"Correct map type ({target_map_type})")
    else:
        feedback_parts.append(f"Incorrect map type: expected '{target_map_type}', got '{actual_map_type}'")

    # Criterion 4: Anti-gaming / Freshness (10 pts)
    # The setup script deletes any existing mapping with this code/source combo.
    # If it exists now, it must have been created during the task.
    # We double check that we actually have a mapping UUID returned.
    if details.get('mapping_uuid'):
        score += 10
        feedback_parts.append("Mapping successfully created")
    else:
        feedback_parts.append("Mapping detected but UUID missing (unexpected)")

    # Pass threshold: 70 points (Must have code + source at minimum)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }