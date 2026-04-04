#!/usr/bin/env python3
"""Verifier for fix_concurrency_race_condition task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_concurrency_race_condition(traj, env_info, task_info):
    """
    Verify that the race condition in InventoryService was fixed.
    
    Scoring:
    - Tests Pass (60 pts): `mvn test` exits 0 and reports no failures.
    - Code Compiles (20 pts): Implied by tests passing, or checked via exit code.
    - Syntax Validity (10 pts): File is modified and looks like Java.
    - Implementation (10 pts): Uses recognized concurrency pattern.
    
    Anti-gaming:
    - Test file must NOT be modified.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    
    # Extract data
    service_content = result.get('service_content', '')
    test_output = result.get('test_output', '')
    mvn_exit_code = result.get('mvn_exit_code', 1)
    tests_run = result.get('tests_run', 0)
    tests_failed = result.get('tests_failed', 0)
    tests_errors = result.get('tests_errors', 0)
    test_file_modified = result.get('test_file_modified', False)
    service_file_modified = result.get('service_file_modified', False)

    # Criterion 1: Test file integrity
    if test_file_modified:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: Test file was modified. You must fix the code, not change the test."
        }

    # Criterion 2: Tests execution (60 pts + 20 pts compile)
    # If mvn exit code is 0, it means compile success + tests passed
    if mvn_exit_code == 0:
        score += 20 # Compile success
        if tests_run > 0 and tests_failed == 0 and tests_errors == 0:
            score += 60 # Tests passed
            feedback_parts.append("Tests passed successfully")
        else:
            feedback_parts.append(f"Build success but tests failed: {tests_failed} failures")
    else:
        # Check if it was a compile error or test failure
        if "COMPILATION ERROR" in test_output:
            feedback_parts.append("Compilation failed")
        else:
            score += 20 # Likely compiled but tests failed
            feedback_parts.append("Tests failed")

    # Criterion 3: Implementation Check (10 pts)
    # Look for concurrency primitives
    keywords = [
        r'\bsynchronized\b',
        r'\bAtomicInteger\b',
        r'\bConcurrentHashMap\b',
        r'\bReentrantLock\b',
        r'\bLock\b',
        r'\bcompute\b', # ConcurrentHashMap atomic methods
        r'\bmerge\b'
    ]
    
    implementation_found = False
    for pattern in keywords:
        if re.search(pattern, service_content):
            implementation_found = True
            break
            
    if implementation_found:
        score += 10
        feedback_parts.append("Concurrency primitives detected")
    else:
        feedback_parts.append("No obvious concurrency primitives found")

    # Criterion 4: Syntax/Modification (10 pts)
    if service_file_modified:
        score += 10
        feedback_parts.append("Service file modified")
    else:
        feedback_parts.append("Service file NOT modified")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }