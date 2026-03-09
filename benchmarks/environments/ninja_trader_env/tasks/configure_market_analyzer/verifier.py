#!/usr/bin/env python3
"""Verifier for configure_market_analyzer task.

Scoring (100 points):
- Subtask 1 (25 pts): Workspace was modified (agent took action and saved)
- Subtask 2 (30 pts): Market Analyzer exists with all 3 instruments (SPY, AAPL, MSFT)
- Subtask 3 (25 pts): RSI indicator column present
- Subtask 4 (20 pts): Last and Net Change columns present

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/NinjaTraderTasks/configure_market_analyzer_result.json"


def verify_configure_market_analyzer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_instruments = set(metadata.get('instruments', ['SPY', 'AAPL', 'MSFT']))

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
        return {"passed": False, "score": 0, "feedback": "Result file not found - export script may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {str(e)}"}

    # GATE 1: If workspace was not modified and no Market Analyzer found, no work was done
    if not result.get('workspace_modified') and not result.get('has_market_analyzer'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No workspace changes detected and no Market Analyzer found - no work done"
        }

    # GATE 2: Wrong-target rejection - at least one required instrument must be present
    instrument_count = result.get('instrument_count', 0)
    if result.get('has_market_analyzer') and instrument_count == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "WRONG TARGET: Market Analyzer created but none of SPY/AAPL/MSFT found"
        }

    score = 0
    feedback_parts = []

    # Subtask 1 (25 pts): Workspace was modified
    try:
        if result.get('workspace_modified'):
            score += 25
            feedback_parts.append("Workspace saved (+25)")
        else:
            feedback_parts.append("Workspace not saved (0)")
    except Exception as e:
        feedback_parts.append(f"Workspace check error: {e}")

    # Subtask 2 (30 pts): Market Analyzer with all 3 instruments
    try:
        if result.get('has_market_analyzer'):
            instrument_count = result.get('instrument_count', 0)
            if instrument_count >= 3:
                score += 30
                feedback_parts.append(f"Market Analyzer with {instrument_count} instruments (+30)")
            elif instrument_count >= 2:
                score += 20
                feedback_parts.append(f"Market Analyzer with {instrument_count}/3 instruments (+20)")
            elif instrument_count >= 1:
                score += 10
                feedback_parts.append(f"Market Analyzer with {instrument_count}/3 instruments (+10)")
            else:
                feedback_parts.append("Market Analyzer found but no instruments detected")
        else:
            feedback_parts.append("No Market Analyzer found (0)")
    except Exception as e:
        feedback_parts.append(f"Market Analyzer check error: {e}")

    # Subtask 3 (25 pts): RSI indicator column
    try:
        if result.get('has_rsi'):
            score += 25
            feedback_parts.append("RSI column present (+25)")
        else:
            feedback_parts.append("RSI column not found (0)")
    except Exception as e:
        feedback_parts.append(f"RSI check error: {e}")

    # Subtask 4 (20 pts): Last and Net Change columns
    try:
        col_score = 0
        if result.get('has_last'):
            col_score += 10
        if result.get('has_net_change'):
            col_score += 10
        score += col_score
        if col_score == 20:
            feedback_parts.append("Last + Net Change columns present (+20)")
        elif col_score > 0:
            feedback_parts.append(f"Partial columns: Last={'Y' if result.get('has_last') else 'N'}, NetChange={'Y' if result.get('has_net_change') else 'N'} (+{col_score})")
        else:
            feedback_parts.append("Last and Net Change columns not found (0)")
    except Exception as e:
        feedback_parts.append(f"Column check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
