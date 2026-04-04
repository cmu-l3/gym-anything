#!/usr/bin/env python3
"""Verifier for import_historical_quotes task."""

import json
import tempfile
import os


def verify_import_historical_quotes(traj, env_info, task_info):
    """Verify historical quotes were imported for Apple Inc."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_quotes = metadata.get('min_quotes_expected', 100)
    expected_start = metadata.get('expected_date_range_start', '2024-01-02')
    expected_end = metadata.get('expected_date_range_end', '2024-06-28')

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/import_quotes_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Portfolio file exists and was modified (15 points)
    if result.get('portfolio_found'):
        score += 5
        feedback.append("Portfolio file found")
        if result.get('file_modified'):
            score += 10
            feedback.append("Portfolio file was modified during task")
        else:
            feedback.append("Portfolio file NOT modified during task")
    else:
        feedback.append("Portfolio file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: AAPL has price data (25 points)
    if result.get('has_aapl_prices'):
        score += 25
        feedback.append(f"Apple Inc has price data: {result.get('aapl_price_count', 0)} quotes")
    else:
        feedback.append("Apple Inc has NO price data")

    # Criterion 3: Sufficient number of quotes imported (20 points)
    aapl_count = result.get('aapl_price_count', 0)
    if aapl_count >= min_quotes:
        score += 20
        feedback.append(f"Quote count ({aapl_count}) meets minimum ({min_quotes})")
    elif aapl_count >= 50:
        score += 10
        feedback.append(f"Partial import: {aapl_count} quotes (expected >= {min_quotes})")
    elif aapl_count > 0:
        score += 5
        feedback.append(f"Few quotes imported: {aapl_count} (expected >= {min_quotes})")
    else:
        feedback.append(f"No quotes imported (expected >= {min_quotes})")

    # Criterion 4: Date range covers expected period (20 points)
    first_date = result.get('first_date', '')
    last_date = result.get('last_date', '')
    if first_date and last_date:
        date_score = 0
        if first_date <= expected_start:
            date_score += 10
            feedback.append(f"Start date OK: {first_date}")
        elif first_date <= '2024-02-01':
            date_score += 5
            feedback.append(f"Start date close: {first_date} (expected <= {expected_start})")
        else:
            feedback.append(f"Start date too late: {first_date} (expected <= {expected_start})")

        if last_date >= expected_end:
            date_score += 10
            feedback.append(f"End date OK: {last_date}")
        elif last_date >= '2024-06-01':
            date_score += 5
            feedback.append(f"End date close: {last_date} (expected >= {expected_end})")
        else:
            feedback.append(f"End date too early: {last_date} (expected >= {expected_end})")
        score += date_score
    else:
        feedback.append("Date range could not be determined")

    # Criterion 5: More prices than initial (20 points)
    initial = result.get('initial_price_count', 0)
    current = result.get('current_price_count', 0)
    if current > initial:
        score += 20
        feedback.append(f"Price count increased: {initial} -> {current}")
    else:
        feedback.append(f"Price count unchanged: {initial} -> {current}")

    passed = score >= 60 and result.get('has_aapl_prices') and aapl_count > 10

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
