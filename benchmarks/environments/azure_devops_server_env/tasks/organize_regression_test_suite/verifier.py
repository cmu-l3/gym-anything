#!/usr/bin/env python3
"""
Verifier for organize_regression_test_suite task.
Checks if the Test Plan was renamed, and suites were organized correctly.
"""

import json
import logging
import os
import tempfile
import sys

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_organize_regression_test_suite(traj, env_info, task_info):
    """
    Verifies that the agent organized the regression test suite correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    remote_path = "C:\\Users\\Docker\\task_result.json"
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Variables
    score = 0
    feedback = []
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_plan_name = metadata.get('expected_plan_name', "v1.0 Release Plan")
    target_static_suite = metadata.get('static_suite_name', "Checkout Module")
    target_query_suite = metadata.get('query_suite_name', "Smoke Tests")
    required_cases = set(metadata.get('target_test_cases', []))

    # 1. Verify Test Plan Name (10 pts)
    plan_name = result.get('plan_name')
    if plan_name == target_plan_name:
        score += 10
        feedback.append(f"✓ Test Plan renamed to '{target_plan_name}'")
    elif result.get('plan_found'):
        feedback.append(f"✗ Test Plan found but named '{plan_name}' instead of '{target_plan_name}'")
    else:
        feedback.append("✗ Test Plan not found")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # 2. Verify Static Suite Creation (10 pts)
    if result.get('static_suite_found'):
        score += 10
        feedback.append(f"✓ Static suite '{target_static_suite}' created")
    else:
        feedback.append(f"✗ Static suite '{target_static_suite}' NOT found")

    # 3. Verify Static Suite Population (40 pts)
    # The agent should add *only* the specific cases.
    found_cases = set(result.get('static_suite_cases', []))
    
    # Check for missing cases
    missing = required_cases - found_cases
    # Check for extra cases (penalize 5 pts each)
    extra = found_cases - required_cases
    
    if not missing and not extra:
        score += 40
        feedback.append(f"✓ '{target_static_suite}' contains exactly the correct test cases")
    else:
        # Partial credit logic
        match_count = len(required_cases) - len(missing)
        points_per_match = 10
        current_points = match_count * points_per_match
        
        # Penalties
        penalty = len(extra) * 5
        final_suite_score = max(0, current_points - penalty)
        
        score += final_suite_score
        
        if missing:
            feedback.append(f"✗ Missing test cases in '{target_static_suite}': {', '.join(missing)}")
        if extra:
            feedback.append(f"✗ Extra test cases in '{target_static_suite}': {', '.join(extra)}")

    # 4. Verify Query Suite Creation (10 pts)
    if result.get('query_suite_found'):
        score += 10
        feedback.append(f"✓ Query suite '{target_query_suite}' created")
    else:
        feedback.append(f"✗ Query suite '{target_query_suite}' NOT found")

    # 5. Verify Query Logic (30 pts)
    # Expect [Priority] = 1 or similar syntax
    query_string = result.get('query_string', '')
    if query_string:
        # Robust check for priority=1 logic
        # WIQL can be "[Microsoft.VSTS.Common.Priority] = 1" or "[Priority] = 1"
        is_priority_check = "priority" in query_string.lower() and "1" in query_string
        
        if is_priority_check:
            score += 30
            feedback.append(f"✓ Query logic correctly filters for Priority 1")
        else:
            feedback.append(f"✗ Query logic incorrect. Expected Priority=1 filter. Got: {query_string}")
    elif result.get('query_suite_found'):
        feedback.append(f"✗ Query suite exists but has no query string")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }