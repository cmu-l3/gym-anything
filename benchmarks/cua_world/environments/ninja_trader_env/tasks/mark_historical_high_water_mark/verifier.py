#!/usr/bin/env python3
"""
Verifier for mark_historical_high_water_mark task.

Task: Identify highest daily close of SPY in 2023 (465.18).
Mark with Horizontal Line and Text.
Export price to text file.

Criteria:
1. Workspace saved (10 pts)
2. SPY Chart created (10 pts)
3. Data loaded correctly (implied by correct marking, 20 pts)
4. Horizontal Line at 465.18 +/- 0.50 (30 pts)
5. Text label "2023 High" (10 pts)
6. Text file with correct price (10 pts)
7. Workflow validated (10 pts)

Total: 100
Pass: 70
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

GROUND_TRUTH_PRICE = 465.18
TOLERANCE = 0.50

def verify_mark_historical_high_water_mark(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container (Export script saves to C:\tmp\task_result.json)
    result_path = "C:/tmp/task_result.json"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Workspace Saved (10 pts)
    if result.get('workspace_saved'):
        score += 10
        feedback_parts.append("Workspace saved (+10)")
    else:
        feedback_parts.append("Workspace NOT saved")

    # 2. Chart Found (10 pts)
    if result.get('chart_found'):
        score += 10
        feedback_parts.append("SPY Chart found (+10)")
    else:
        feedback_parts.append("SPY Chart NOT found")

    # 3. Horizontal Line Accuracy (30 pts)
    # 4. Data Series Loaded (20 pts - awarded if line is correct)
    line_price = result.get('horizontal_line_price')
    line_correct = False
    
    if line_price is not None:
        diff = abs(float(line_price) - GROUND_TRUTH_PRICE)
        if diff <= TOLERANCE:
            score += 30 # Line accuracy
            score += 20 # Data loaded (implied)
            line_correct = True
            feedback_parts.append(f"Line price correct: {line_price} (+50)")
        else:
            feedback_parts.append(f"Line price incorrect: {line_price} (Expected ~{GROUND_TRUTH_PRICE})")
            score += 5 # Partial credit
    else:
        feedback_parts.append("Horizontal line not found")

    # If line was not correct but data series loaded flag is true
    if not line_correct and result.get('data_series_loaded'):
        score += 10
        feedback_parts.append("Data series configured correctly (+10)")

    # 5. Text Label (10 pts)
    if result.get('text_label_found'):
        score += 10
        feedback_parts.append("Text label found (+10)")
    else:
        feedback_parts.append("Text label missing")

    # 6. Text File Output (10 pts)
    file_val = result.get('output_file_value')
    if file_val is not None:
        try:
            val = float(file_val)
            if abs(val - GROUND_TRUTH_PRICE) <= TOLERANCE:
                score += 10
                feedback_parts.append("Output file correct (+10)")
            else:
                feedback_parts.append(f"Output file value incorrect: {val}")
        except:
            feedback_parts.append("Output file content not numeric")
    else:
        feedback_parts.append("Output file missing")

    # 7. Workflow/Activity Check (10 pts)
    # Grant if substantial work was done
    if score >= 50:
        score += 10
        feedback_parts.append("Workflow validated (+10)")

    return {
        "passed": score >= 70,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }