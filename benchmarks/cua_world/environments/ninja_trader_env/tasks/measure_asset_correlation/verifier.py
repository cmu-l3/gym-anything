#!/usr/bin/env python3
"""
Verifier for measure_asset_correlation task.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_measure_asset_correlation(traj, env_info, task_info):
    """
    Verify the correlation measurement task.
    
    Criteria:
    1. Workspace modified (10 pts)
    2. AAPL and MSFT present in workspace (25 pts)
    3. Correlation indicator configured with Period 20 (25 pts)
    4. Report file exists with numeric value (10 pts)
    5. Reported value is reasonably close to ground truth (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth_value', 0.42) # Fallback if not set
    tolerance = metadata.get('tolerance', 0.1)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: export_result.ps1 saved to C:\workspace\data\task_result.json
        # which maps to /workspace/data/task_result.json in the container usually,
        # or we might need to adjust based on how copy_from_env works with Windows paths.
        # Assuming standard mapping or copy support.
        copy_from_env("C:\\workspace\\data\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Workspace Modified (10 pts)
    if result.get('workspace_modified', False):
        score += 10
        feedback_parts.append("Workspace saved (+10)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")

    # Analyze Workspace Content
    ws_content = result.get('workspace_content_snippet', '')
    
    # 2. Instruments Check (25 pts)
    # Check for AAPL and MSFT
    has_aapl = 'AAPL' in ws_content or 'Apple' in ws_content
    has_msft = 'MSFT' in ws_content or 'Microsoft' in ws_content
    
    if has_aapl and has_msft:
        score += 25
        feedback_parts.append("Both AAPL and MSFT found in chart (+25)")
    elif has_aapl or has_msft:
        score += 10
        feedback_parts.append("Only one instrument found (+10)")
    else:
        feedback_parts.append("Instruments not found in workspace (0)")

    # 3. Indicator Check (25 pts)
    # Look for Correlation and Period="20"
    # Regex for Correlation indicator in XML might vary, but "Correlation" string is standard
    has_correlation = 'Correlation' in ws_content
    # Check period. XML usually looks like <Period>20</Period> or property="Period" value="20"
    # Simple check for "20" near Correlation is risky, but strict XML parsing is hard on snippet.
    # We'll look for the string "20" in the content if Correlation is present.
    has_period_20 = '20' in ws_content
    
    if has_correlation:
        if has_period_20:
            score += 25
            feedback_parts.append("Correlation (20) configured (+25)")
        else:
            score += 15
            feedback_parts.append("Correlation found but period 20 not confirmed (+15)")
    else:
        feedback_parts.append("Correlation indicator not found (0)")

    # 4. Report Existence (10 pts)
    report_exists = result.get('report_exists', False)
    reported_val_raw = result.get('report_value')
    
    if report_exists and result.get('report_created_during_task'):
        score += 10
        feedback_parts.append("Report file created (+10)")
    elif report_exists:
        score += 5
        feedback_parts.append("Report file exists but old timestamp (+5)")
    else:
        feedback_parts.append("Report file missing (0)")

    # 5. Value Accuracy (30 pts)
    value_correct = False
    try:
        if reported_val_raw is not None:
            val = float(reported_val_raw)
            # Check against ground truth
            diff = abs(val - ground_truth)
            if diff <= tolerance:
                score += 30
                value_correct = True
                feedback_parts.append(f"Value {val} is correct within tolerance (+30)")
            else:
                score += 5 # Partial for at least reporting a number
                feedback_parts.append(f"Value {val} outside tolerance {ground_truth} +/- {tolerance} (+5)")
        else:
            feedback_parts.append("No numeric value found in report (0)")
    except ValueError:
        feedback_parts.append("Reported value not a number (0)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }