#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_concept_class(traj, env_info, task_info):
    """
    Verifies the creation of the Concept Class 'PRAPARE Assessment'.
    
    Scoring Criteria:
    - Class Exists (40 pts)
    - Correct Abbreviation (30 pts)
    - Correct Description (20 pts)
    - Not Retired (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "PRAPARE Assessment")
    expected_desc = metadata.get('expected_description', "Social determinants of health assessment concepts")
    expected_abbr = metadata.get('expected_abbreviation', "PRAPARE")

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Class Exists (40 pts)
    if result.get('class_found'):
        score += 40
        feedback_parts.append("Concept Class found.")
    else:
        return {"passed": False, "score": 0, "feedback": "Concept Class 'PRAPARE Assessment' was not found in the system."}

    # Criterion 2: Correct Abbreviation (30 pts)
    # Note: OpenMRS allows case-sensitivity, but usually abbreviations are caps. Description asked for "PRAPARE".
    actual_abbr = result.get('abbreviation', '')
    if actual_abbr == expected_abbr:
        score += 30
        feedback_parts.append("Abbreviation is correct.")
    else:
        feedback_parts.append(f"Abbreviation mismatch. Expected '{expected_abbr}', got '{actual_abbr}'.")

    # Criterion 3: Correct Description (20 pts)
    # Allow partial match (case-insensitive) for robustness
    actual_desc = result.get('description', '')
    if expected_desc.lower() in (actual_desc or '').lower():
        score += 20
        feedback_parts.append("Description is correct.")
    else:
        feedback_parts.append(f"Description mismatch. Expected containing '{expected_desc}', got '{actual_desc}'.")

    # Criterion 4: Not Retired (10 pts)
    if result.get('retired') is False:
        score += 10
        feedback_parts.append("Class is active (not retired).")
    else:
        feedback_parts.append("Class is marked as retired.")

    # Pass Threshold: 70 points
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }