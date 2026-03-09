#!/usr/bin/env python3
"""Verifier for dual_chart_technical_setup task.

Scoring (100 points):
- Subtask 1 (20 pts): Workspace modified (agent saved work)
- Subtask 2 (25 pts): AAPL chart with SMA indicators
- Subtask 3 (25 pts): MSFT chart with EMA/Bollinger/MACD
- Subtask 4 (15 pts): Volume present on AAPL chart
- Subtask 5 (15 pts): Both instruments present (two distinct charts)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/NinjaTraderTasks/dual_chart_technical_setup_result.json"


def verify_dual_chart_technical_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})

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

    # GATE: If no workspace modification and no instruments found, no work done
    if not result.get('workspace_modified') and not result.get('has_aapl') and not result.get('has_msft'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No workspace changes and no chart instruments detected"
        }

    score = 0
    feedback_parts = []

    # Subtask 1 (20 pts): Workspace modified
    try:
        if result.get('workspace_modified'):
            score += 20
            feedback_parts.append("Workspace saved (+20)")
        else:
            feedback_parts.append("Workspace not saved (0)")
    except Exception as e:
        feedback_parts.append(f"Workspace check error: {e}")

    # Subtask 2 (25 pts): AAPL chart with SMA indicators
    try:
        aapl_score = 0
        if result.get('has_aapl') and result.get('has_sma'):
            aapl_score = 25
            feedback_parts.append("AAPL chart with SMA (+25)")
        elif result.get('has_aapl'):
            aapl_score = 10
            feedback_parts.append("AAPL chart found but SMA missing (+10)")
        elif result.get('has_sma'):
            aapl_score = 5
            feedback_parts.append("SMA found but AAPL chart missing (+5)")
        else:
            feedback_parts.append("AAPL chart with SMA not found (0)")
        score += aapl_score
    except Exception as e:
        feedback_parts.append(f"AAPL chart check error: {e}")

    # Subtask 3 (25 pts): MSFT chart with EMA/Bollinger/MACD
    try:
        msft_score = 0
        msft_indicators = sum([
            1 if result.get('has_ema') else 0,
            1 if result.get('has_bollinger') else 0,
            1 if result.get('has_macd') else 0
        ])
        if result.get('has_msft') and msft_indicators >= 3:
            msft_score = 25
            feedback_parts.append("MSFT chart with EMA+Bollinger+MACD (+25)")
        elif result.get('has_msft') and msft_indicators >= 2:
            msft_score = 18
            feedback_parts.append(f"MSFT chart with {msft_indicators}/3 indicators (+18)")
        elif result.get('has_msft') and msft_indicators >= 1:
            msft_score = 10
            feedback_parts.append(f"MSFT chart with {msft_indicators}/3 indicators (+10)")
        elif result.get('has_msft'):
            msft_score = 5
            feedback_parts.append("MSFT chart found but indicators missing (+5)")
        else:
            feedback_parts.append("MSFT chart with indicators not found (0)")
        score += msft_score
    except Exception as e:
        feedback_parts.append(f"MSFT chart check error: {e}")

    # Subtask 4 (15 pts): Volume on AAPL chart
    try:
        if result.get('has_volume'):
            score += 15
            feedback_parts.append("Volume indicator present (+15)")
        else:
            feedback_parts.append("Volume indicator not found (0)")
    except Exception as e:
        feedback_parts.append(f"Volume check error: {e}")

    # Subtask 5 (15 pts): Both instruments present
    try:
        if result.get('both_instruments'):
            score += 15
            feedback_parts.append("Both AAPL and MSFT present (+15)")
        elif result.get('has_aapl') or result.get('has_msft'):
            score += 5
            feedback_parts.append("Only one instrument found (+5)")
        else:
            feedback_parts.append("No instruments found (0)")
    except Exception as e:
        feedback_parts.append(f"Instrument check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
