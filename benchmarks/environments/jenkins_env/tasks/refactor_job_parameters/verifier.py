#!/usr/bin/env python3
"""
Verifier for Refactor Job Parameters task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_job_parameters(traj, env_info, task_info):
    """
    Verifies that the agent refactored the job to use parameters correctly.
    
    Criteria:
    1. Job has a parameter named 'TARGET_ENV'.
    2. Parameter is a Choice Parameter.
    3. Choices match exactly (development, staging, production).
    4. Functional Test: A build triggered with TARGET_ENV=staging outputs "Deploying service to staging environment...".
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_param = metadata.get('param_name', 'TARGET_ENV')
    expected_choices = metadata.get('param_choices', ['development', 'staging', 'production'])
    
    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/refactor_job_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback = []
    
    config = result.get('config', {})
    func_test = result.get('functional_test', {})
    
    # 1. Check Parameter Name (20 pts)
    actual_param = config.get('param_name', '')
    if actual_param == expected_param:
        score += 20
        feedback.append(f"Correct parameter '{expected_param}' added.")
    else:
        feedback.append(f"Parameter '{expected_param}' not found (found: '{actual_param}').")
        
    # 2. Check Parameter Type (10 pts)
    # Expected: hudson.model.ChoiceParameterDefinition
    actual_type = config.get('param_type', '')
    if 'ChoiceParameterDefinition' in actual_type:
        score += 10
        feedback.append("Parameter is correctly set as Choice Parameter.")
    else:
        feedback.append(f"Parameter type incorrect (expected Choice, got {actual_type}).")
        
    # 3. Check Choices (20 pts)
    actual_choices_csv = config.get('choices_csv', '')
    # Normalize for comparison
    actual_choices = [c.strip() for c in actual_choices_csv.split(',') if c.strip()]
    
    # Sort for set comparison if order doesn't matter, but usually order matters in UI.
    # We'll be lenient on order but strict on content.
    if set(actual_choices) == set(expected_choices):
        score += 20
        feedback.append("Parameter choices are correct.")
    else:
        feedback.append(f"Choices incorrect. Expected {expected_choices}, got {actual_choices}.")

    # 4. Check Script Update (Variable Usage) (20 pts)
    if config.get('script_has_variable'):
        score += 20
        feedback.append("Build script updated to use variable.")
    else:
        feedback.append("Build script does not appear to use $TARGET_ENV or ${TARGET_ENV}.")
        
    # 5. Functional Test (30 pts)
    # This confirms the script actually works at runtime
    if func_test.get('output_correct'):
        score += 30
        feedback.append("Verification build produced correct dynamic output.")
    else:
        feedback.append("Verification build failed to produce expected output (script logic may be wrong).")
        
    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }