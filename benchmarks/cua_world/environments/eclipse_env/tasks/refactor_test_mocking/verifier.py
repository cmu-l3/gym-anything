#!/usr/bin/env python3
"""Verifier for refactor_test_mocking task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_test_mocking(traj, env_info, task_info):
    """Verify that the test was refactored to use Mockito and passes.

    Criteria:
    1. Test compiles and runs successfully (40 pts)
    2. Mockito is used (imports and method calls) (20 pts)
    3. Real StripePaymentProcessor dependency is removed (20 pts)
    4. Test file was modified during the task (10 pts)
    5. VLM visual confirmation of Eclipse/JUnit state (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    test_content = result.get('test_content', '')
    maven_output = result.get('maven_output', '')
    
    # --- Criterion 1: Test Execution (40 pts) ---
    tests_passed = result.get('tests_passed', False)
    run_count = result.get('tests_run_count', '0')
    failures = result.get('failures_count', '0')
    errors = result.get('errors_count', '0')
    
    if tests_passed:
        try:
            rc = int(run_count)
            if rc > 0:
                score += 40
                feedback_parts.append("Tests passed successfully")
            else:
                feedback_parts.append("Build success but no tests ran")
        except ValueError:
             feedback_parts.append("Error parsing test counts")
    else:
        feedback_parts.append("Maven test run failed")
        # Check if it was a compilation error or test failure
        if "COMPILATION ERROR" in maven_output:
            feedback_parts.append("(Compilation Error)")
        else:
            feedback_parts.append(f"(Failures: {failures}, Errors: {errors})")

    # --- Criterion 2: Mockito Usage (20 pts) ---
    mockito_score = 0
    if 'org.mockito' in test_content:
        mockito_score += 10
    
    # Look for common mockito patterns
    patterns = [
        r'Mockito\.mock\(',
        r'@Mock',
        r'Mockito\.when\(',
        r'when\(.*\.processPayment',
        r'given\(.*\.processPayment',
        r'doReturn\(.*\)'
    ]
    
    found_patterns = [p for p in patterns if re.search(p, test_content)]
    if found_patterns:
        mockito_score += 10
        feedback_parts.append(f"Mockito usage detected ({len(found_patterns)} patterns)")
    else:
        feedback_parts.append("No Mockito stubbing methods found")
        
    score += mockito_score

    # --- Criterion 3: Dependency Decoupling (20 pts) ---
    # We want to ensure `new StripePaymentProcessor()` is NOT present
    if 'new StripePaymentProcessor()' in test_content:
        feedback_parts.append("FAILED: Test still instantiates real StripePaymentProcessor")
    else:
        score += 20
        feedback_parts.append("Real dependency removed")

    # --- Criterion 4: Anti-Gaming (10 pts) ---
    if result.get('file_modified', False):
        score += 10
    else:
        feedback_parts.append("Test file was not modified")

    # --- Criterion 5: VLM Verification (10 pts) ---
    # Use the shared utility to check for visual evidence
    try:
        from utils.eclipse_verification_utils import vlm_verify_eclipse_task
        
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Refactor a failing test to use Mockito mocks instead of real objects",
            checklist_items=[
                "Eclipse IDE is open",
                "JUnit view shows a green bar (passing tests)",
                "Code editor shows usage of Mockito (e.g., mock(), when())",
                "The 'Red Bar' of failure was replaced by 'Green Bar'"
            ]
        )
        
        if vlm_result and vlm_result.get('vlm_passed'):
            score += 10
            feedback_parts.append("Visual verification passed")
        elif vlm_result:
            feedback_parts.append(f"Visual verification warning: {vlm_result.get('vlm_feedback')}")
            
    except ImportError:
        # Fallback if utils not available
        pass

    passed = score >= 80 and tests_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }