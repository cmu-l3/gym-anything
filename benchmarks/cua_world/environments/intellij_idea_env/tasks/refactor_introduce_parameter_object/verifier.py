#!/usr/bin/env python3
"""Verifier for refactor_introduce_parameter_object task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_refactor_parameter_object(traj, env_info, task_info):
    """Verify that Introduce Parameter Object refactoring was applied correctly.

    Criteria:
    1. Project compiles and tests pass (30 pts)
    2. TransactionRequest.java exists (20 pts)
    3. PaymentProcessor signature updated to use TransactionRequest (20 pts)
    4. TransactionRequest class contains correct fields (10 pts)
    5. Callers (App.java, Test) updated to use new object (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_fields = set(metadata.get('expected_fields', ["merchantId", "amount", "currency", "cardNum", "cvv", "expiry", "note"]))

    score = 0
    feedback_parts = []

    # Get result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification data: {e}"}

    # --- Criterion 1: Build & Test Success (30 pts) ---
    if result.get('build_success', False):
        score += 30
        feedback_parts.append("Project compiles and tests pass")
    else:
        feedback_parts.append("Build/Test failed")

    # --- Criterion 2: New Class Exists (20 pts) ---
    if result.get('new_class_exists', False):
        score += 20
        feedback_parts.append("TransactionRequest class created")
    else:
        feedback_parts.append("TransactionRequest class NOT found")

    # --- Criterion 3: Signature Update (20 pts) ---
    processor_content = result.get('processor_content', '')
    # Check that the long parameter list is GONE
    has_long_params = "String merchantId, double amount" in processor_content
    # Check that the new parameter is PRESENT
    has_new_param = "TransactionRequest" in processor_content

    if not has_long_params and has_new_param:
        score += 20
        feedback_parts.append("Method signature updated correctly")
    elif has_new_param:
        score += 10
        feedback_parts.append("Method takes TransactionRequest but old params might linger?")
    else:
        feedback_parts.append("Method signature NOT updated")

    # --- Criterion 4: Fields in New Class (10 pts) ---
    new_class_content = result.get('new_class_content', '')
    found_fields = 0
    for field in expected_fields:
        if field in new_class_content:
            found_fields += 1
    
    if found_fields == len(expected_fields):
        score += 10
        feedback_parts.append("All fields preserved in new class")
    elif found_fields > 0:
        partial = int(10 * (found_fields / len(expected_fields)))
        score += partial
        feedback_parts.append(f"Some fields preserved ({found_fields}/{len(expected_fields)})")
    else:
        feedback_parts.append("Fields missing in new class")

    # --- Criterion 5: Callers Updated (20 pts) ---
    # We check if the caller code instantiates the new object
    app_content = result.get('app_content', '')
    test_content = result.get('test_content', '')
    
    callers_updated = 0
    if "new TransactionRequest" in app_content or "TransactionRequest" in app_content:
        callers_updated += 1
    
    if "new TransactionRequest" in test_content or "TransactionRequest" in test_content:
        callers_updated += 1

    if callers_updated == 2:
        score += 20
        feedback_parts.append("Callers (App and Test) updated")
    elif callers_updated == 1:
        score += 10
        feedback_parts.append("Only some callers updated")
    else:
        # If build passed, maybe they did something else? But sticking to requirement.
        if result.get('build_success', False):
            # If build passed but we don't see explicit new keywords, maybe they used a builder?
            # Trust the build success a bit more here
            score += 10
            feedback_parts.append("Callers likely updated (build passed)")
        else:
            feedback_parts.append("Callers NOT updated")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }