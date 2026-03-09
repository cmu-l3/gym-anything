#!/usr/bin/env python3
"""Verifier for break_circular_deps task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_break_circular_deps(traj, env_info, task_info):
    """
    Verify that circular dependencies between Model and Service packages are removed.
    
    Criteria:
    1. No imports of 'com.example.order.service' in 'com.example.order.model' (30 pts)
    2. Project compiles successfully (20 pts)
    3. All 8 tests pass (25 pts)
    4. Order.java specifically fixed (10 pts)
    5. Customer.java specifically fixed (10 pts)
    6. Logic preserved (5 pts - verified via passing tests)
    
    Total: 100 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Read result from container
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
    
    # Criterion 1: Circular Dependencies Removed (30 pts)
    circular_deps_found = result.get('circular_deps_found', True)
    if not circular_deps_found:
        score += 30
        feedback_parts.append("Circular dependencies removed (No service imports in model)")
    else:
        violations = result.get('violations', '')
        feedback_parts.append(f"Circular dependencies still present: {violations}")
        
    # Criterion 2: Compilation (20 pts)
    build_success = result.get('build_success', False)
    if build_success:
        score += 20
        feedback_parts.append("Project compiles successfully")
    else:
        feedback_parts.append("Project build failed")
        
    # Criterion 3: Tests Pass (25 pts)
    tests_run = result.get('tests_run', 0)
    tests_failed = result.get('tests_failed', 0)
    expected_tests = task_info.get('metadata', {}).get('expected_test_count', 8)
    
    if tests_run >= expected_tests and tests_failed == 0:
        score += 25
        feedback_parts.append(f"All {tests_run} tests passed")
    elif tests_run > 0:
        # Partial credit for running tests but failing some
        pass_rate = (tests_run - tests_failed) / max(tests_run, 1)
        pts = int(15 * pass_rate)
        score += pts
        feedback_parts.append(f"{tests_run - tests_failed}/{tests_run} tests passed")
    else:
        feedback_parts.append("No tests run")
        
    # Criterion 4: Order.java fixed (10 pts)
    if result.get('order_fixed', False):
        score += 10
        feedback_parts.append("Order.java dependency fixed")
        
    # Criterion 5: Customer.java fixed (10 pts)
    if result.get('customer_fixed', False):
        score += 10
        feedback_parts.append("Customer.java dependency fixed")
        
    # Criterion 6: Logic Preserved (5 pts)
    # We assume if tests pass and build succeeds, logic is preserved
    if build_success and tests_run >= expected_tests and tests_failed == 0:
        score += 5
        feedback_parts.append("Logic preserved")

    passed = score >= 65 and build_success and not circular_deps_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }