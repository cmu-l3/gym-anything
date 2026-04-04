#!/usr/bin/env python3
"""Verifier for edit_uml_class_diagram task.
Checks if a Payment class was added to the e-commerce UML class diagram.
"""

import json
import tempfile
import os


def verify_edit_uml_class_diagram(traj, env_info, task_info):
    """Verify that a Payment class was added to the UML diagram."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})

    # Copy result from container
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
    criteria_met = 0
    total_criteria = 7

    # Criterion 1: File exists and was modified (15 points)
    if result.get('file_exists') and result.get('file_modified'):
        score += 15
        criteria_met += 1
        feedback_parts.append("File saved with changes")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("File exists but may not be modified")
    else:
        feedback_parts.append("FAIL: Diagram file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Payment class exists (20 points)
    if result.get('has_payment_class'):
        score += 20
        criteria_met += 1
        feedback_parts.append("Payment class found")
    else:
        feedback_parts.append("FAIL: Payment class NOT found")

    # Criterion 3: Payment attributes - paymentId (10 points)
    if result.get('has_payment_id'):
        score += 10
        criteria_met += 1
        feedback_parts.append("paymentId attribute found")
    else:
        feedback_parts.append("Missing paymentId attribute")

    # Criterion 4: Payment attributes - amount (10 points)
    if result.get('has_amount'):
        score += 10
        criteria_met += 1
        feedback_parts.append("amount attribute found")
    else:
        feedback_parts.append("Missing amount attribute")

    # Criterion 5: Payment attributes - paymentDate or method (10 points)
    if result.get('has_payment_date') or result.get('has_method_attr'):
        score += 10
        criteria_met += 1
        extra_attrs = []
        if result.get('has_payment_date'):
            extra_attrs.append("paymentDate")
        if result.get('has_method_attr'):
            extra_attrs.append("method")
        feedback_parts.append(f"Additional attributes: {', '.join(extra_attrs)}")
    else:
        feedback_parts.append("Missing paymentDate and method attributes")

    # Criterion 6: Methods present (15 points)
    has_methods = result.get('has_process_payment') or result.get('has_refund')
    if has_methods:
        score += 15
        criteria_met += 1
        methods = []
        if result.get('has_process_payment'):
            methods.append("processPayment")
        if result.get('has_refund'):
            methods.append("refund")
        feedback_parts.append(f"Methods: {', '.join(methods)}")
    else:
        feedback_parts.append("Missing methods (processPayment/refund)")

    # Criterion 7: New connection added (20 points)
    new_connections = result.get('new_connections', 0)
    if new_connections >= 1:
        score += 20
        criteria_met += 1
        feedback_parts.append(f"New connections: {new_connections}")
    else:
        feedback_parts.append("No new connections drawn")

    # Pass requires:
    # 1. Score >= 65
    # 2. Payment class must exist
    # 3. At least 2 attributes found
    # 4. At least 1 new connection
    has_payment = result.get('has_payment_class', False)
    attr_count = sum([
        result.get('has_payment_id', False),
        result.get('has_amount', False),
        result.get('has_payment_date', False),
        result.get('has_method_attr', False)
    ])
    has_connection = new_connections >= 1

    passed = (score >= 65 and
              has_payment and
              attr_count >= 2 and
              has_connection)

    if passed:
        feedback_parts.append("UML class diagram updated successfully!")
    else:
        reasons = []
        if not has_payment:
            reasons.append("Payment class missing")
        if attr_count < 2:
            reasons.append(f"only {attr_count} attributes (need 2+)")
        if not has_connection:
            reasons.append("no new connections")
        if score < 65:
            reasons.append(f"score {score} < 65")
        feedback_parts.append(f"FAILED: {'; '.join(reasons)}")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "file_modified": result.get('file_modified', False),
            "has_payment_class": has_payment,
            "attribute_count": attr_count,
            "new_connections": new_connections,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
