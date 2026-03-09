#!/usr/bin/env python3
"""
Verifier for refactor_constructor_to_builder task.

Criteria:
1. Project compiles (25 pts)
2. All tests pass (25 pts)
3. SmartHomeDevice.java implements Builder pattern (20 pts)
4. SmartHomeDevice public constructor is removed/hidden (10 pts)
5. Service and Test usages updated to use Builder (20 pts)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_constructor_to_builder(traj, env_info, task_info):
    """Verify the refactoring from constructor to builder pattern."""
    
    # 1. Setup - get result from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Verify Compilation (25 pts)
    if result.get('compile_success', False):
        score += 25
        feedback.append("Project compiles successfully.")
    else:
        feedback.append("Project failed to compile.")

    # 3. Verify Tests (25 pts)
    if result.get('tests_passed', False):
        score += 25
        feedback.append("All tests passed.")
    else:
        feedback.append("Tests failed.")

    # Get file contents
    model_code = result.get('model_content', '')
    service_code = result.get('service_content', '')
    test_code = result.get('test_content', '')

    # 4. Verify Builder Implementation (20 pts)
    # Look for a static inner class Builder OR a static method builder()
    has_builder_class = re.search(r'static\s+class\s+Builder', model_code)
    has_builder_method = re.search(r'static\s+.*Builder\s+builder\(\)', model_code)
    has_build_method = re.search(r'public\s+SmartHomeDevice\s+build\(\)', model_code)
    
    # Also support Lombok @Builder if they managed to add the library (unlikely but valid)
    has_lombok_builder = '@Builder' in model_code

    if (has_builder_class or has_builder_method or has_lombok_builder) and (has_build_method or has_lombok_builder):
        score += 20
        feedback.append("Builder pattern structure detected in SmartHomeDevice.")
    else:
        feedback.append("Builder pattern structure NOT detected in SmartHomeDevice.")

    # 5. Verify Constructor Visibility (10 pts)
    # The public constructor with 7 args should be gone or made private
    # Regex: public SmartHomeDevice( -> look for this specific signature
    # Since we might have a public empty constructor for other reasons, check specifically for the large one
    has_public_large_ctor = re.search(r'public\s+SmartHomeDevice\s*\(\s*UUID', model_code)
    
    if not has_public_large_ctor:
        score += 10
        feedback.append("Large public constructor removed or hidden.")
    else:
        feedback.append("Large public constructor still exists.")

    # 6. Verify Usage Updates (20 pts)
    # Check that client code uses .build() and not new SmartHomeDevice(...)
    # We check for the ABSENCE of `new SmartHomeDevice(` in service and test
    
    # Note: If they used `new SmartHomeDevice.Builder()`, that starts with `new SmartHomeDevice`, 
    # so we need to be careful.
    # The pattern we want to ban is `new SmartHomeDevice(arg, arg...)`
    
    # Regex look for `new SmartHomeDevice(` followed by something other than `)` (empty) or `.Builder`
    # Simple check: count usages of `.build()` vs `new SmartHomeDevice`
    
    uses_build_service = '.build()' in service_code
    uses_build_test = '.build()' in test_code
    
    # Strict check: Service should not use the 7-arg constructor
    # We check if `new SmartHomeDevice(` is followed by arguments
    uses_old_ctor_service = re.search(r'new\s+SmartHomeDevice\s*\([^)]+,', service_code)
    uses_old_ctor_test = re.search(r'new\s+SmartHomeDevice\s*\([^)]+,', test_code)

    if uses_build_service and uses_build_test and not uses_old_ctor_service and not uses_old_ctor_test:
        score += 20
        feedback.append("Client code (Service and Test) correctly updated to use Builder.")
    elif uses_build_service or uses_build_test:
        score += 10
        feedback.append("Partial update of client code to Builder.")
    else:
        feedback.append("Client code does not appear to use the Builder.")

    # Anti-gaming check
    if not result.get('file_modified', False):
        score = 0
        feedback = ["Files were not modified. No work detected."]

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }