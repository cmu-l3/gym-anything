#!/usr/bin/env python3
"""Verifier for optimize_strategy_parameters task.

Scoring (100 points):
- Subtask 1 (20 pts): Export file exists at expected path
- Subtask 2 (25 pts): File has valid structure with multiple rows
- Subtask 3 (25 pts): File contains MSFT-related data
- Subtask 4 (15 pts): File suggests multiple parameter combinations
- Subtask 5 (15 pts): File contains performance metrics

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/NinjaTraderTasks/optimize_strategy_parameters_result.json"


def verify_optimize_strategy_parameters(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_instrument = metadata.get('instrument', 'MSFT')

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

    # GATE 1: If no output file exists, no work was done
    if not result.get('file_exists') and not result.get('alt_file_found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No optimization export file found"
        }

    # GATE 2: Wrong-target rejection - if file exists but target instrument is absent
    if result.get('file_exists') and result.get('line_count', 0) > 3 and not result.get('has_msft'):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"WRONG TARGET: Export file exists but {expected_instrument} data not found - optimized wrong instrument"
        }

    score = 0
    feedback_parts = []

    # Subtask 1 (20 pts): Export file exists
    try:
        if result.get('file_exists'):
            score += 20
            feedback_parts.append("Export file at correct path (+20)")
        elif result.get('alt_file_found'):
            score += 10
            alt = result.get('alt_file_path', 'unknown')
            feedback_parts.append(f"Export file at alt path: {alt} (+10)")
        else:
            feedback_parts.append("Export file not found (0)")
    except Exception as e:
        feedback_parts.append(f"File check error: {e}")

    # Subtask 2 (25 pts): Valid structure with multiple rows
    try:
        line_count = result.get('line_count', 0)
        file_size = result.get('file_size', 0)
        if result.get('has_multiple_rows') and file_size >= 200:
            score += 25
            feedback_parts.append(f"Valid structure: {line_count} lines, {file_size} bytes (+25)")
        elif line_count >= 2 and file_size >= 50:
            score += 12
            feedback_parts.append(f"Partial structure: {line_count} lines (+12)")
        else:
            feedback_parts.append("File too small or empty (0)")
    except Exception as e:
        feedback_parts.append(f"Structure check error: {e}")

    # Subtask 3 (25 pts): Contains MSFT data
    try:
        if result.get('has_msft'):
            score += 25
            feedback_parts.append("MSFT data found (+25)")
        else:
            # Partial credit if file has substantial content
            if result.get('line_count', 0) > 5:
                score += 8
                feedback_parts.append("File has data but MSFT not detected (+8)")
            else:
                feedback_parts.append("MSFT data not found (0)")
    except Exception as e:
        feedback_parts.append(f"MSFT check error: {e}")

    # Subtask 4 (15 pts): Multiple parameter combinations
    try:
        if result.get('has_parameter_variation'):
            score += 15
            feedback_parts.append("Parameter variation detected (+15)")
        elif result.get('has_multiple_rows'):
            score += 8
            feedback_parts.append("Multiple rows but parameter variation unclear (+8)")
        else:
            feedback_parts.append("Parameter variation not detected (0)")
    except Exception as e:
        feedback_parts.append(f"Parameter check error: {e}")

    # Subtask 5 (15 pts): Performance metrics present
    try:
        if result.get('has_performance_metrics'):
            score += 15
            feedback_parts.append("Performance metrics found (+15)")
        else:
            feedback_parts.append("Performance metrics not found (0)")
    except Exception as e:
        feedback_parts.append(f"Metrics check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
