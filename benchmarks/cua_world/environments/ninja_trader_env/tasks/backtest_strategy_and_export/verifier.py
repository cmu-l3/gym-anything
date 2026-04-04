#!/usr/bin/env python3
"""Verifier for backtest_strategy_and_export task.

Scoring (100 points):
- Subtask 1 (20 pts): Export file exists at the expected path
- Subtask 2 (25 pts): File is non-empty with valid CSV/text structure
- Subtask 3 (25 pts): File contains SPY trade data
- Subtask 4 (15 pts): Trades are within expected date range (2023-2024)
- Subtask 5 (15 pts): File contains both buy and sell entries (complete trades)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/NinjaTraderTasks/backtest_strategy_and_export_result.json"


def verify_backtest_strategy_and_export(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_instrument = metadata.get('instrument', 'SPY')

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        try:
            copy_from_env(RESULT_PATH, temp_path)
            with open(temp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {str(e)}"}

    # GATE 1: If no output file exists (and no alt file), no work was done
    if not result.get('file_exists') and not result.get('alt_file_found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No export file found at expected path or alternatives"
        }

    # GATE 2: Wrong-target rejection - if file exists but target instrument is absent
    if result.get('file_exists') and result.get('line_count', 0) > 3 and not result.get('has_spy'):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"WRONG TARGET: Export file exists but {expected_instrument} data not found - backtested wrong instrument"
        }

    score = 0
    feedback_parts = []

    # Subtask 1 (20 pts): Export file exists
    try:
        if result.get('file_exists'):
            score += 20
            feedback_parts.append("Export file exists at correct path (+20)")
        elif result.get('alt_file_found'):
            score += 10
            alt = result.get('alt_file_path', 'unknown')
            feedback_parts.append(f"Export file found at alternate path: {alt} (+10)")
        else:
            feedback_parts.append("Export file not found (0)")
    except Exception as e:
        feedback_parts.append(f"File existence check error: {e}")

    # Subtask 2 (25 pts): File has valid structure
    try:
        line_count = result.get('line_count', 0)
        file_size = result.get('file_size', 0)
        if line_count >= 3 and file_size >= 100:
            score += 25
            feedback_parts.append(f"Valid file structure: {line_count} lines, {file_size} bytes (+25)")
        elif line_count >= 1 and file_size > 0:
            score += 10
            feedback_parts.append(f"File exists but small: {line_count} lines (+10)")
        else:
            feedback_parts.append("File empty or invalid structure (0)")
    except Exception as e:
        feedback_parts.append(f"Structure check error: {e}")

    # Subtask 3 (25 pts): Contains SPY trade data
    try:
        if result.get('has_spy'):
            score += 25
            feedback_parts.append("SPY instrument data found (+25)")
        else:
            # Partial credit if file has content but SPY not detected
            if result.get('line_count', 0) > 3:
                score += 5
                feedback_parts.append("File has data but SPY not detected (+5)")
            else:
                feedback_parts.append("SPY data not found (0)")
    except Exception as e:
        feedback_parts.append(f"SPY data check error: {e}")

    # Subtask 4 (15 pts): Date range matches 2023-2024
    try:
        if result.get('has_date_range'):
            score += 15
            feedback_parts.append("Date range 2023-2024 detected (+15)")
        else:
            feedback_parts.append("Expected date range not detected (0)")
    except Exception as e:
        feedback_parts.append(f"Date range check error: {e}")

    # Subtask 5 (15 pts): Has buy and sell entries
    try:
        buy_sell_score = 0
        if result.get('has_buy_entries'):
            buy_sell_score += 8
        if result.get('has_sell_entries'):
            buy_sell_score += 7
        score += buy_sell_score
        if buy_sell_score == 15:
            feedback_parts.append("Buy and sell entries present (+15)")
        elif buy_sell_score > 0:
            feedback_parts.append(f"Partial trade entries: buy={'Y' if result.get('has_buy_entries') else 'N'}, sell={'Y' if result.get('has_sell_entries') else 'N'} (+{buy_sell_score})")
        else:
            feedback_parts.append("No buy/sell entries detected (0)")
    except Exception as e:
        feedback_parts.append(f"Trade entries check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
