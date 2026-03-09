#!/usr/bin/env python3
"""
Verifier for add_custom_drug task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_custom_drug(traj, env_info, task_info):
    """
    Verify that the custom drug was added to the OSCAR EMR database with correct details.
    
    Scoring Criteria:
    - Record exists (40 pts)
    - Generic name matches (15 pts)
    - Strength matches (15 pts)
    - Form matches (15 pts)
    - Route matches (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Get metadata (expected values)
    metadata = task_info.get('metadata', {})
    expected_brand = metadata.get('expected_brand', 'Menthol 1% Cream').lower()
    expected_generic = metadata.get('expected_generic', 'Menthol').lower()
    expected_strength = metadata.get('expected_strength', '1%')
    expected_form = metadata.get('expected_form', 'Cream').lower()
    expected_route = metadata.get('expected_route', 'Topical').lower()

    # 2. Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Evaluate results
    score = 0
    feedback = []
    
    drug_found = result.get('drug_found', False)
    details = result.get('drug_details', {})
    
    if not drug_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Custom drug record 'Menthol 1% Cream' was not found in the database."
        }

    # Criterion 1: Record Exists
    score += 40
    feedback.append("Success: Drug record created.")

    # Criterion 2: Generic Name
    # Use loose matching for safety (case insensitive, partials)
    actual_generic = details.get('generic_name', '').lower()
    if expected_generic in actual_generic:
        score += 15
        feedback.append(f"Generic name correct ({details.get('generic_name')}).")
    else:
        feedback.append(f"Generic name incorrect. Expected '{expected_generic}', got '{actual_generic}'.")

    # Criterion 3: Strength
    # Handle spacing variations "1%" vs "1 %"
    actual_strength = details.get('strength', '').replace(' ', '')
    clean_expected_strength = expected_strength.replace(' ', '')
    if clean_expected_strength in actual_strength:
        score += 15
        feedback.append(f"Strength correct ({details.get('strength')}).")
    else:
        feedback.append(f"Strength incorrect. Expected '{expected_strength}', got '{details.get('strength')}'.")

    # Criterion 4: Form
    actual_form = details.get('form', '').lower()
    if expected_form in actual_form:
        score += 15
        feedback.append(f"Dosage form correct ({details.get('form')}).")
    else:
        feedback.append(f"Dosage form incorrect. Expected '{expected_form}', got '{actual_form}'.")

    # Criterion 5: Route
    # Allow 'Topical' or 'TOP'
    actual_route = details.get('route', '').lower()
    if expected_route in actual_route or 'top' in actual_route:
        score += 15
        feedback.append(f"Route correct ({details.get('route')}).")
    else:
        feedback.append(f"Route incorrect. Expected '{expected_route}', got '{actual_route}'.")

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }