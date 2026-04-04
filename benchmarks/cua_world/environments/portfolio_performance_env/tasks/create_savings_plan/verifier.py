#!/usr/bin/env python3
"""Verifier for create_savings_plan task."""

import json
import tempfile
import os


def verify_create_savings_plan(traj, env_info, task_info):
    """Verify a monthly savings plan was created correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_isin = metadata.get('expected_security_isin', 'IE00B3RBWM25')
    expected_amount = metadata.get('expected_amount', 50000) # 500.00 EUR
    expected_interval = metadata.get('expected_interval', 'MONTHLY')
    expected_start = metadata.get('expected_start_date', '2026-04-01')

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/savings_plan_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: File Saved (10 points)
    if result.get('file_exists') and result.get('file_modified'):
        score += 10
        feedback.append("Portfolio saved")
    elif result.get('file_exists'):
        feedback.append("Portfolio exists but not saved/modified")
    else:
        return {"passed": False, "score": 0, "feedback": "Portfolio file not found"}

    # Criterion 2: Plan Created (30 points)
    if result.get('plan_found') and result.get('plans_count', 0) > 0:
        score += 30
        feedback.append("Savings plan created")
    else:
        feedback.append("No savings plan found in file")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Criterion 3: Correct Security (20 points)
    # The ISIN extracted by export script might be inferred, but we verify it matches expected
    if result.get('security_isin') == expected_isin:
        score += 20
        feedback.append(f"Security correct ({expected_isin})")
    else:
        feedback.append(f"Security mismatch or not identified")

    # Criterion 4: Correct Amount (20 points)
    actual_amount = result.get('amount', 0)
    if actual_amount == expected_amount:
        score += 20
        feedback.append(f"Amount correct ({actual_amount/100:.2f})")
    else:
        feedback.append(f"Amount incorrect: {actual_amount/100:.2f} (expected {expected_amount/100:.2f})")

    # Criterion 5: Correct Interval (10 points)
    if result.get('interval') == expected_interval:
        score += 10
        feedback.append(f"Interval correct ({expected_interval})")
    else:
        feedback.append(f"Interval incorrect: {result.get('interval')} (expected {expected_interval})")

    # Criterion 6: Correct Start Date (10 points)
    if result.get('start_date') == expected_start:
        score += 10
        feedback.append(f"Start date correct ({expected_start})")
    else:
        feedback.append(f"Start date incorrect: {result.get('start_date')} (expected {expected_start})")

    # Penalty if transaction created instead of plan?
    # Task is to create a plan. If they created a transaction (BUY) for 2026, it's wrong.
    # But usually <booking-plan> is distinct from <portfolio-transaction>.
    # The verifier checks for plan presence.

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }