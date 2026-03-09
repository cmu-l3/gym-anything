#!/usr/bin/env python3
"""Verifier for add_security_and_buy task."""

import json
import tempfile
import os


def verify_add_security_and_buy(traj, env_info, task_info):
    """Verify a new security was added AND a buy transaction recorded."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_new_security', 'Alphabet Inc Class A')
    expected_ticker = metadata.get('expected_ticker', 'GOOGL')
    expected_isin = metadata.get('expected_isin', 'US02079K3059')
    expected_shares = metadata.get('expected_shares', 15)
    expected_total = metadata.get('expected_total_value', 2100.00)
    expected_fees = metadata.get('expected_fees', 9.99)
    expected_date = metadata.get('expected_buy_date', '2024-03-10')
    tolerance = metadata.get('value_tolerance', 100.00)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/add_security_buy_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Portfolio file modified (5 points)
    if result.get('portfolio_found') and result.get('file_modified'):
        score += 5
        feedback.append("Portfolio saved")
    elif result.get('portfolio_found'):
        feedback.append("Portfolio found but may not be saved")
    else:
        return {"passed": False, "score": 0, "feedback": "Portfolio file not found"}

    # Criterion 2: New security was added (15 points)
    initial_sec = result.get('initial_sec_count', 0)
    current_sec = result.get('current_sec_count', 0)
    if current_sec > initial_sec:
        score += 15
        feedback.append(f"New security added ({initial_sec} -> {current_sec})")
    else:
        feedback.append(f"No new security detected ({initial_sec} -> {current_sec})")

    # Criterion 3: GOOGL/Alphabet security found (20 points)
    if result.get('googl_security_found'):
        score += 15
        feedback.append(f"Alphabet/GOOGL security found: {result.get('googl_name')}")

        # Check ticker
        if result.get('googl_ticker', '').upper() in ['GOOGL', 'GOOG']:
            score += 2
            feedback.append(f"Ticker: {result.get('googl_ticker')}")

        # Check ISIN
        if result.get('googl_isin') == expected_isin:
            score += 3
            feedback.append(f"ISIN correct: {result.get('googl_isin')}")
    else:
        # Partial credit if any new security was added
        if current_sec > initial_sec:
            score += 5
            all_secs = result.get('all_securities', [])
            new_names = [s.get('name', '') for s in all_secs]
            feedback.append(f"New security added but not Alphabet/GOOGL. Securities: {new_names}")
        else:
            feedback.append("Alphabet/GOOGL security NOT found")

    # Criterion 4: GOOGL buy transaction found (20 points)
    if result.get('googl_buy_found'):
        score += 20
        feedback.append("GOOGL BUY transaction found")
    else:
        # Check if any new transaction was added
        initial_txn = result.get('initial_txn_count', 0)
        current_txn = result.get('current_txn_count', 0)
        if current_txn > initial_txn:
            score += 8
            feedback.append(f"New transaction added ({initial_txn} -> {current_txn}) but not confirmed as GOOGL buy")
        else:
            feedback.append("GOOGL BUY transaction NOT found")

    # Criterion 5: Correct shares (10 points)
    actual_shares = result.get('googl_buy_shares', 0)
    if abs(actual_shares - expected_shares) < 0.01:
        score += 10
        feedback.append(f"Shares correct: {actual_shares}")
    elif actual_shares > 0:
        score += 3
        feedback.append(f"Shares: {actual_shares} (expected {expected_shares})")

    # Criterion 6: Correct amount (10 points)
    actual_amount = result.get('googl_buy_amount', 0)
    if abs(actual_amount - expected_total) <= tolerance:
        score += 10
        feedback.append(f"Amount correct: ${actual_amount:.2f}")
    elif actual_amount > 0:
        score += 3
        feedback.append(f"Amount: ${actual_amount:.2f} (expected ~${expected_total:.2f})")

    # Criterion 7: Correct date (10 points)
    actual_date = result.get('googl_buy_date', '')
    if expected_date in actual_date:
        score += 10
        feedback.append(f"Date correct: {actual_date}")
    elif '2024-03' in actual_date:
        score += 5
        feedback.append(f"Date in March 2024: {actual_date} (expected {expected_date})")

    # Criterion 8: Fees (5 points)
    actual_fees = result.get('googl_buy_fees', 0)
    if abs(actual_fees - expected_fees) < 2.0:
        score += 5
        feedback.append(f"Fees correct: ${actual_fees:.2f}")

    # Both security AND transaction required
    has_security = result.get('googl_security_found') or current_sec > initial_sec
    has_transaction = result.get('googl_buy_found') or result.get('current_txn_count', 0) > result.get('initial_txn_count', 0)
    passed = score >= 55 and has_security and has_transaction

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
