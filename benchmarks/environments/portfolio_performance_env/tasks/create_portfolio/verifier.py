#!/usr/bin/env python3
"""Verifier for create_portfolio task."""

import json
import tempfile
import os


def verify_create_portfolio(traj, env_info, task_info):
    """Verify a new portfolio was created with correct structure."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_portfolio_name', 'retirement_portfolio')
    expected_currency = metadata.get('expected_currency', 'USD')
    expected_sec_account = metadata.get('expected_securities_account', 'Retirement Account')
    expected_cash_account = metadata.get('expected_cash_account', 'Retirement Account (USD)')

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_portfolio_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Portfolio file exists (20 points)
    if result.get('portfolio_found'):
        score += 20
        feedback.append("Portfolio file found")
    else:
        feedback.append("Portfolio file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Portfolio name matches (15 points)
    portfolio_name = result.get('portfolio_name', '').lower()
    if expected_name.lower() in portfolio_name or 'retirement' in portfolio_name:
        score += 15
        feedback.append(f"Portfolio name matches: {result.get('portfolio_name')}")
    else:
        feedback.append(f"Portfolio name mismatch: expected '{expected_name}', got '{result.get('portfolio_name')}'")

    # Criterion 3: Currency is USD (15 points)
    file_currency = result.get('file_currency', '')
    if file_currency.upper() == expected_currency:
        score += 15
        feedback.append(f"Currency correct: {file_currency}")
    elif file_currency:
        score += 5
        feedback.append(f"Currency set but wrong: expected '{expected_currency}', got '{file_currency}'")
    else:
        feedback.append("Currency not detected")

    # Criterion 4: Has securities account (20 points)
    sec_name = result.get('securities_account_name', '')
    cash_name = result.get('cash_account_name', '')
    if result.get('has_securities_account'):
        score += 15
        feedback.append("Securities account exists")
        # Check name - require it to match expected AND be distinct from cash account
        if sec_name and expected_sec_account.lower() == sec_name.lower():
            score += 5
            feedback.append(f"Securities account name correct: {sec_name}")
        elif sec_name and 'retirement' in sec_name.lower():
            # Partial credit if name contains 'retirement' but isn't exact match
            # But penalize if it's the same as cash account name (wrong naming)
            if sec_name.lower() != cash_name.lower():
                score += 3
                feedback.append(f"Securities account name partial match: {sec_name} (expected: {expected_sec_account})")
            else:
                score += 1
                feedback.append(f"Securities account name same as cash account: {sec_name} (should be distinct)")
        elif sec_name:
            score += 2
            feedback.append(f"Securities account name: {sec_name} (expected: {expected_sec_account})")
    else:
        feedback.append("No securities account found")

    # Criterion 5: Has cash/deposit account (20 points)
    if result.get('has_cash_account'):
        score += 15
        feedback.append("Cash account exists")
        # Check name - require it to match expected AND be distinct from securities account
        if cash_name and expected_cash_account.lower() == cash_name.lower():
            score += 5
            feedback.append(f"Cash account name correct: {cash_name}")
        elif cash_name and ('retirement' in cash_name.lower() or 'usd' in cash_name.lower()):
            if cash_name.lower() != sec_name.lower():
                score += 3
                feedback.append(f"Cash account name partial match: {cash_name} (expected: {expected_cash_account})")
            else:
                score += 1
                feedback.append(f"Cash account name same as securities account: {cash_name} (should be distinct)")
        elif cash_name:
            score += 2
            feedback.append(f"Cash account name: {cash_name} (expected: {expected_cash_account})")
    else:
        feedback.append("No cash account found")

    # Criterion 6: New file was created (10 points)
    initial = result.get('initial_file_count', 0)
    current = result.get('current_file_count', 0)
    if current > initial:
        score += 10
        feedback.append(f"New file created (was {initial}, now {current})")
    else:
        feedback.append("No new file detected in target directory")

    # Determine pass/fail
    passed = score >= 60 and result.get('portfolio_found') and (
        result.get('has_securities_account') or result.get('has_cash_account')
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
