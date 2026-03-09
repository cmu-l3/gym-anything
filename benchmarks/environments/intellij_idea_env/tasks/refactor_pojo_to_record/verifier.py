#!/usr/bin/env python3
"""Verifier for refactor_pojo_to_record task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_refactor_pojo_to_record(traj, env_info, task_info):
    """
    Verify the refactoring of a POJO to a Java Record.

    Scoring Criteria:
    1. TransactionEvent is a record (30 pts)
    2. Boilerplate (explicit getters, etc) removed (10 pts)
    3. AuditService updated to use record accessors (15 pts)
    4. Test class updated to use record accessors (15 pts)
    5. Validation logic (compact constructor) preserved (10 pts)
    6. Build and tests pass (20 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    event_content = result.get("event_content", "")
    service_content = result.get("service_content", "")
    test_content = result.get("test_content", "")
    test_result = result.get("test_result", "unknown")
    
    # Criterion 1: TransactionEvent is a record (30 pts)
    # Regex checks for 'public record TransactionEvent'
    if re.search(r'public\s+record\s+TransactionEvent', event_content):
        score += 30
        feedback_parts.append("TransactionEvent converted to record")
    else:
        feedback_parts.append("TransactionEvent is NOT a record")

    # Criterion 2: Boilerplate removed (10 pts)
    # Records shouldn't have explicit getters like getAmount() unless manually added (unlikely here)
    has_get_amount = "getAmount()" in event_content
    has_to_string = "public String toString()" in event_content
    if not has_get_amount and not has_to_string:
        score += 10
        feedback_parts.append("Boilerplate getters removed")
    elif has_get_amount:
        feedback_parts.append("Explicit getter 'getAmount()' still present")

    # Criterion 3: AuditService updated (15 pts)
    # Should see event.amount() instead of event.getAmount()
    if "event.amount()" in service_content and "event.getAmount()" not in service_content:
        score += 15
        feedback_parts.append("AuditService updated correctly")
    elif "event.getAmount()" in service_content:
        feedback_parts.append("AuditService still uses 'getAmount()'")

    # Criterion 4: Test class updated (15 pts)
    # Should see event.amount() instead of event.getAmount()
    if "event.amount()" in test_content and "event.getAmount()" not in test_content:
        score += 15
        feedback_parts.append("TransactionEventTest updated correctly")
    elif "event.getAmount()" in test_content:
        feedback_parts.append("Tests still use 'getAmount()'")

    # Criterion 5: Validation logic preserved (10 pts)
    # Look for constructor/compact constructor validation
    has_validation = "amount.compareTo(BigDecimal.ZERO) <= 0" in event_content
    if has_validation:
        score += 10
        feedback_parts.append("Constructor validation logic preserved")
    else:
        feedback_parts.append("Constructor validation logic seems missing")

    # Criterion 6: Build and tests pass (20 pts)
    if test_result == "pass":
        score += 20
        feedback_parts.append("Build and tests passed")
    else:
        feedback_parts.append("Build/Tests failed")

    # Anti-gaming check
    if not result.get("file_modified", False) and score > 0:
        score = 0
        feedback_parts = ["Files were not modified during the task"]

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }