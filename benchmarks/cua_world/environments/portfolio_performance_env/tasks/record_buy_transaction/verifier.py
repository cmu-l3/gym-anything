#!/usr/bin/env python3
"""Verifier for record_buy_transaction task."""

import json
import tempfile
import os


def verify_record_buy_transaction(traj, env_info, task_info):
    """Verify a MSFT buy transaction was recorded correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_shares = metadata.get('expected_shares', 8)
    expected_total = metadata.get('expected_total_value', 3360.00)
    expected_fees = metadata.get('expected_fees', 9.99)
    expected_date = metadata.get('expected_date', '2024-04-15')
    tolerance = metadata.get('value_tolerance', 50.00)

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/buy_txn_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Portfolio exists and was modified (10 points)
    if result.get('portfolio_found'):
        score += 5
        feedback.append("Portfolio found")
        if result.get('file_modified'):
            score += 5
            feedback.append("File modified during task")
    else:
        return {"passed": False, "score": 0, "feedback": "Portfolio file not found"}

    # Criterion 2: New transaction was added (15 points)
    new_count = result.get('new_txn_count', 0)
    if new_count > 0:
        score += 15
        feedback.append(f"New transaction(s) added: {new_count}")
    else:
        feedback.append("No new transactions detected")

    # Criterion 3: MSFT buy transaction found (25 points)
    if result.get('msft_buy_found'):
        score += 25
        feedback.append("Microsoft Corp BUY transaction found")
    else:
        # Check if any buy was added
        buy_txns = [t for t in result.get('all_txns', []) if t.get('type') == 'BUY']
        if len(buy_txns) > 1:  # Original AAPL buy + new one
            score += 10
            feedback.append(f"Buy transaction found but not confirmed as MSFT ({len(buy_txns)} total buys)")
        else:
            feedback.append("MSFT BUY transaction NOT found")

    # Criterion 4: Correct number of shares (15 points)
    actual_shares = result.get('msft_buy_shares', 0)
    if abs(actual_shares - expected_shares) < 0.01:
        score += 15
        feedback.append(f"Shares correct: {actual_shares}")
    elif actual_shares > 0:
        score += 5
        feedback.append(f"Shares recorded but wrong: {actual_shares} (expected {expected_shares})")
    else:
        feedback.append(f"Shares not detected (expected {expected_shares})")

    # Criterion 5: Correct total value (15 points)
    actual_amount = result.get('msft_buy_amount', 0)
    if abs(actual_amount - expected_total) <= tolerance:
        score += 15
        feedback.append(f"Amount correct: ${actual_amount:.2f}")
    elif actual_amount > 0:
        score += 5
        feedback.append(f"Amount recorded: ${actual_amount:.2f} (expected ~${expected_total:.2f})")
    else:
        feedback.append(f"Amount not detected (expected ~${expected_total:.2f})")

    # Criterion 6: Correct date (10 points)
    actual_date = result.get('msft_buy_date', '')
    if expected_date in actual_date:
        score += 10
        feedback.append(f"Date correct: {actual_date}")
    elif actual_date:
        score += 3
        feedback.append(f"Date recorded: {actual_date} (expected {expected_date})")
    else:
        feedback.append(f"Date not detected (expected {expected_date})")

    # Criterion 7: Fees recorded (10 points)
    actual_fees = result.get('msft_buy_fees', 0)
    if abs(actual_fees - expected_fees) < 1.0:
        score += 10
        feedback.append(f"Fees correct: ${actual_fees:.2f}")
    elif actual_fees > 0:
        score += 5
        feedback.append(f"Fees recorded: ${actual_fees:.2f} (expected ${expected_fees:.2f})")

    passed = score >= 60 and result.get('msft_buy_found')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
