#!/usr/bin/env python3
"""
Verifier for create_concept task in OpenMRS.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_concept(traj, env_info, task_info):
    """
    Verify the creation of the medical concept.
    
    Criteria:
    1. Concept 'Toluene Exposure' exists and is active (30 pts)
    2. Correct Class 'Diagnosis' (20 pts)
    3. Correct Datatype 'N/A' (20 pts)
    4. Correct Synonym 'Methylbenzene exp' (15 pts)
    5. Correct Description (15 pts)
    
    Anti-gaming: Must be created during the task session.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_class = metadata.get('expected_class', 'Diagnosis')
    expected_datatype = metadata.get('expected_datatype', 'N/A')
    expected_description_part = "Occupational exposure" # Partial match check

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

    score = 0
    feedback = []

    # 1. Check Existence & Freshness
    concept_exists = result.get('concept_exists', False)
    created_fresh = result.get('created_during_task', False)
    
    if not concept_exists:
        return {"passed": False, "score": 0, "feedback": "Concept 'Toluene Exposure' was not found in the dictionary."}
    
    if not created_fresh:
        # Penalize but don't fail completely if close, but instruction says "Create".
        # If setup works correctly, old one is renamed, so finding one means it was created.
        # This check is a backup.
        feedback.append("Warning: Concept creation timestamp is older than task start.")
    else:
        score += 30
        feedback.append("Concept created successfully.")

    # 2. Check Class
    actual_class = result.get('class_name', '')
    if actual_class.lower() == expected_class.lower():
        score += 20
        feedback.append(f"Class correct ({actual_class}).")
    else:
        feedback.append(f"Class mismatch: expected {expected_class}, got '{actual_class}'.")

    # 3. Check Datatype
    actual_datatype = result.get('datatype_name', '')
    if actual_datatype.lower() == expected_datatype.lower():
        score += 20
        feedback.append(f"Datatype correct ({actual_datatype}).")
    else:
        feedback.append(f"Datatype mismatch: expected {expected_datatype}, got '{actual_datatype}'.")

    # 4. Check Synonym
    if result.get('synonym_exists', False):
        score += 15
        feedback.append("Synonym 'Methylbenzene exp' added.")
    else:
        feedback.append("Synonym 'Methylbenzene exp' missing.")

    # 5. Check Description
    actual_desc = result.get('description', '')
    if expected_description_part.lower() in actual_desc.lower():
        score += 15
        feedback.append("Description matches.")
    else:
        feedback.append(f"Description mismatch or missing. Got: '{actual_desc}'")

    # Pass Threshold
    # Must have existence + class + datatype to be usable (30+20+20 = 70)
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }