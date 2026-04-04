#!/usr/bin/env python3
"""Verifier for create_reusable_chart_template task.

Scoring (100 points):
- Subtask 1 (25 pts): Template file exists with correct name
- Subtask 2 (25 pts): Template contains EMA indicators (ideally 2)
- Subtask 3 (25 pts): Template contains RSI and MACD
- Subtask 4 (15 pts): Template has substantial content (not a stub)
- Subtask 5 (10 pts): Workspace was also saved

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/NinjaTraderTasks/create_reusable_chart_template_result.json"


def verify_create_reusable_chart_template(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_template = metadata.get('template_name', 'SwingTrading')

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

    # GATE: If no template found and no new templates, no work was done
    if not result.get('template_found') and not result.get('new_templates'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No chart template created"
        }

    score = 0
    feedback_parts = []

    # Subtask 1 (25 pts): Template exists with correct name
    try:
        if result.get('template_found'):
            score += 25
            feedback_parts.append(f"SwingTrading template found (+25)")
        elif result.get('new_templates'):
            # Agent created a template with wrong name — partial credit
            score += 10
            names = result.get('new_templates', [])
            feedback_parts.append(f"Template created but wrong name: {names} (+10)")
        else:
            feedback_parts.append("No template found (0)")
    except Exception as e:
        feedback_parts.append(f"Template check error: {e}")

    # Subtask 2 (25 pts): Template contains EMA indicators
    try:
        if result.get('has_ema'):
            ema_count = result.get('ema_count', 0)
            if ema_count >= 2:
                score += 25
                feedback_parts.append(f"EMA indicators found ({ema_count} instances) (+25)")
            else:
                score += 15
                feedback_parts.append(f"EMA found but only {ema_count} instance (+15)")
        else:
            feedback_parts.append("EMA indicators not found (0)")
    except Exception as e:
        feedback_parts.append(f"EMA check error: {e}")

    # Subtask 3 (25 pts): Template contains RSI and MACD
    try:
        osc_score = 0
        if result.get('has_rsi'):
            osc_score += 13
        if result.get('has_macd'):
            osc_score += 12
        score += osc_score
        if osc_score == 25:
            feedback_parts.append("RSI + MACD present (+25)")
        elif osc_score > 0:
            feedback_parts.append(f"Partial oscillators: RSI={'Y' if result.get('has_rsi') else 'N'}, MACD={'Y' if result.get('has_macd') else 'N'} (+{osc_score})")
        else:
            feedback_parts.append("RSI and MACD not found (0)")
    except Exception as e:
        feedback_parts.append(f"Oscillator check error: {e}")

    # Subtask 4 (15 pts): Template has substantial content
    try:
        template_size = result.get('template_size', 0)
        if template_size >= 500:
            score += 15
            feedback_parts.append(f"Template substantial ({template_size} bytes) (+15)")
        elif template_size >= 100:
            score += 8
            feedback_parts.append(f"Template small ({template_size} bytes) (+8)")
        else:
            feedback_parts.append(f"Template too small ({template_size} bytes) (0)")
    except Exception as e:
        feedback_parts.append(f"Size check error: {e}")

    # Subtask 5 (10 pts): Workspace saved
    try:
        if result.get('workspace_modified'):
            score += 10
            feedback_parts.append("Workspace also saved (+10)")
        else:
            feedback_parts.append("Workspace not saved (0)")
    except Exception as e:
        feedback_parts.append(f"Workspace check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
