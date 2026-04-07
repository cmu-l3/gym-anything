#!/usr/bin/env python3
"""
Verifier for add_drug_formulary task.

Criteria:
1. Drug entry exists in database (30 pts)
2. Drug is NOT retired (10 pts)
3. Concept is correctly linked to "Aspirin" (20 pts)
4. Strength is exactly "500" (20 pts)
5. Creation timestamp is after task start (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_drug_formulary(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Aspirin 500mg ES')
    expected_concept = metadata.get('expected_concept', 'Aspirin')
    expected_strength = metadata.get('expected_strength', '500')

    # Copy result
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
    feedback = []

    # 1. Check existence
    if result.get('drug_found', False):
        score += 30
        feedback.append("Drug entry found in database.")
    else:
        return {"passed": False, "score": 0, "feedback": "Drug 'Aspirin 500mg ES' was not found in the database."}

    # 2. Check retired status (0 = active, 1 = retired)
    # Note: DB usually returns 0 or 1. JSON might have bool or int.
    is_retired = result.get('is_retired')
    if is_retired in [0, "0", False, "false"]:
        score += 10
        feedback.append("Drug is active (not retired).")
    else:
        feedback.append("Drug is marked as retired/voided.")

    # 3. Check Concept Link
    # Logic: The export script joins with concept_name table
    linked_concept = result.get('linked_concept_name', '')
    # Check for "Aspirin" (case-insensitive)
    if expected_concept.lower() in linked_concept.lower():
        score += 20
        feedback.append(f"Correctly linked to concept '{linked_concept}'.")
    else:
        feedback.append(f"Incorrect concept link. Expected '{expected_concept}', found '{linked_concept}'.")

    # 4. Check Strength
    strength = str(result.get('drug_strength', ''))
    # Clean up any decimals if it's "500.0"
    if strength.endswith(".0"):
        strength = strength[:-2]
    
    if strength == expected_strength:
        score += 20
        feedback.append(f"Strength correctly set to {strength}.")
    else:
        feedback.append(f"Incorrect strength. Expected '{expected_strength}', found '{strength}'.")

    # 5. Anti-gaming: Created during task
    if result.get('created_during_task', False):
        score += 20
        feedback.append("Drug was created during the task session.")
    else:
        feedback.append("Drug creation timestamp predates task start (or could not be verified).")

    # Final Check
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }