#!/usr/bin/env python3
"""
Verifier for Characterize Novel GHG Flow task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_characterize_novel_ghg_flow(traj, env_info, task_info):
    """
    Verify that the agent correctly characterized the novel GHG flow.
    
    Criteria:
    1. Flow Created (20 pts): 'HFC-Experimental' exists in DB.
    2. Method Created (20 pts): 'Expanded' method exists in DB.
    3. Characterization (30 pts): Flow is linked to Global Warming category with value 2300.
    4. Calculation (20 pts): Output CSV exists and contains the result (2300).
    5. Process/Validity (10 pts): File created during task + VLM confirmation.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Flow Creation (20 pts) ---
    if result.get("flow_found", False):
        score += 20
        feedback.append("Flow 'HFC-Experimental' created successfully.")
    else:
        feedback.append("Flow 'HFC-Experimental' NOT found in database.")

    # --- Criterion 2: Method Creation (20 pts) ---
    if result.get("method_found", False):
        score += 20
        feedback.append("Impact method created.")
    else:
        feedback.append("Custom Impact method NOT found.")

    # --- Criterion 3: Characterization Factor (30 pts) ---
    # This is the core 'Anti-Gaming' check. Did they actually modify the method?
    if result.get("factor_found", False):
        score += 30
        feedback.append("Characterization factor (2300) correctly linked.")
    else:
        feedback.append("Characterization factor NOT correct (expected 2300 linked to flow).")

    # --- Criterion 4: Calculation Output (20 pts) ---
    output_exists = result.get("output_exists", False)
    value_correct = result.get("output_contains_value", False)
    
    if output_exists and value_correct:
        score += 20
        feedback.append("Calculation result exported and correct.")
    elif output_exists:
        score += 10
        feedback.append("Result file exists but does not contain expected value (2300).")
    else:
        feedback.append("No result file exported.")

    # --- Criterion 5: Validity (10 pts) ---
    # Check if file was created during task (not pre-existing)
    if result.get("output_created_during_task", False):
        score += 10
    
    # Calculate Final Status
    # Pass threshold: Must have Flow + Method + Factor correct (70 pts minimum logic)
    # The actual numeric threshold is usually set here.
    passed = (score >= 70) and result.get("factor_found", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }