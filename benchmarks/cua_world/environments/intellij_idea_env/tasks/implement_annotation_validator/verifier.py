#!/usr/bin/env python3
"""
Verifier for implement_annotation_validator task.

Criteria:
1. Compilation success (15 pts)
2. Reflection usage in Validator.java (15 pts) - Anti-hardcoding check
3. Correct Annotation Definitions (Runtime Retention) (15 pts)
4. Tests Passed (55 pts, scaled)
   - Must pass all 14 tests for full points
   - Partial credit allowed
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_annotation_validator(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    
    # Check 1: Compilation
    # Note: mvn test returning 0 means success. Returning 1 might mean test failure OR compile failure.
    # We check if tests_run > 0 to confirm compilation worked at least partially.
    tests_run = result.get("tests_run", 0)
    tests_passed = result.get("tests_passed", 0)
    
    if tests_run > 0:
        score += 15
        feedback_parts.append("Project compiles")
    else:
        feedback_parts.append("Project failed to compile or run tests")
        return {"passed": False, "score": 0, "feedback": "Compilation failed"}

    # Check 2: Reflection Usage (Anti-gaming / hardcoding check)
    validator_code = result.get("validator_content", "")
    reflection_terms = ["getDeclaredFields", "Field", "getAnnotation", "setAccessible"]
    
    found_terms = [term for term in reflection_terms if term in validator_code]
    
    if len(found_terms) >= 3:
        score += 15
        feedback_parts.append("Validator uses Reflection API")
    else:
        feedback_parts.append(f"Validator missing Reflection calls (found: {found_terms})")
        # Penalty for not using reflection
    
    # Check 3: Annotation Definitions
    # Annotations must have @Retention(RetentionPolicy.RUNTIME) to work with reflection
    notnull_code = result.get("notnull_content", "")
    range_code = result.get("range_content", "")
    
    has_runtime = "RetentionPolicy.RUNTIME" in notnull_code or "Retention(RUNTIME)" in notnull_code
    has_target = "ElementType.FIELD" in notnull_code or "Target(FIELD)" in notnull_code
    
    if has_runtime and has_target:
        score += 15
        feedback_parts.append("Annotations defined correctly with RUNTIME retention")
    elif has_runtime:
        score += 10
        feedback_parts.append("Annotations have RUNTIME retention but missing explicit TARGET")
    else:
        feedback_parts.append("Annotations missing RUNTIME retention (Reflection won't work)")

    # Check 4: Test Results (Scaled)
    # Total tests: 14. Points available: 55
    # Points per test ~= 3.9
    
    test_score = 0
    if tests_run > 0:
        test_score = int((tests_passed / 14.0) * 55)
        score += test_score
        feedback_parts.append(f"Tests passed: {tests_passed}/14")

    # Check 5: Test Modification (Anti-gaming)
    if result.get("test_file_modified", False):
        score = 0
        feedback_parts = ["CRITICAL: Test file was modified. Score reset to 0."]

    passed = score >= 60 and tests_passed >= 8
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }