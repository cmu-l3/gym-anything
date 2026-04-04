#!/usr/bin/env python3
"""
Verifier for generate_profit_loss_report task.
"""

import json
import re
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_profit_loss_report(traj, env_info, task_info):
    """
    Verifies the Profit & Loss report task.
    
    Criteria:
    1. Output file exists and was created during task.
    2. File contains "Total Income", "Total Expenses", "Net Profit".
    3. Values match expected ground truth (from task metadata).
    4. VLM verification: Agent navigated to Reports module.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_income = metadata.get('expected_income', 11300.0)
    expected_expenses = metadata.get('expected_expenses', 3200.0)
    expected_net_profit = metadata.get('expected_net_profit', 8100.0)
    tolerance = metadata.get('tolerance_percent', 5) / 100.0

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check file existence and timestamp (20 pts)
    if result.get('output_exists') and result.get('file_created_during_task'):
        score += 20
        feedback_parts.append("Report file created.")
    elif result.get('output_exists'):
        score += 10
        feedback_parts.append("Report file exists but timestamp check failed.")
    else:
        feedback_parts.append("Report file NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # 2. Parse Content (60 pts)
    content = result.get('report_content', "")
    
    # Helper to extract value by label
    def extract_val(label):
        # Match "Label: 1234.56" or "Label: $1,234.56"
        pattern = re.compile(rf"{label}[:\s]+.*?([\d,]+\.?\d*)", re.IGNORECASE)
        m = pattern.search(content)
        if m:
            try:
                # Remove commas and convert
                return float(m.group(1).replace(',', ''))
            except ValueError:
                return None
        return None

    # Check Income
    income_val = extract_val("Total Income")
    if income_val is not None:
        if abs(income_val - expected_income) <= (expected_income * tolerance):
            score += 20
            feedback_parts.append(f"Income correct ({income_val}).")
        else:
            feedback_parts.append(f"Income incorrect (Got {income_val}, Expected {expected_income}).")
    else:
        feedback_parts.append("Total Income not found in file.")

    # Check Expenses
    expenses_val = extract_val("Total Expenses")
    if expenses_val is not None:
        if abs(expenses_val - expected_expenses) <= (expected_expenses * tolerance):
            score += 20
            feedback_parts.append(f"Expenses correct ({expenses_val}).")
        else:
            feedback_parts.append(f"Expenses incorrect (Got {expenses_val}, Expected {expected_expenses}).")
    else:
        feedback_parts.append("Total Expenses not found in file.")

    # Check Net Profit
    profit_val = extract_val("Net Profit")
    if profit_val is not None:
        if abs(profit_val - expected_net_profit) <= (expected_net_profit * tolerance):
            score += 20
            feedback_parts.append(f"Net Profit correct ({profit_val}).")
        else:
            feedback_parts.append(f"Net Profit incorrect (Got {profit_val}, Expected {expected_net_profit}).")
    else:
        feedback_parts.append("Net Profit not found in file.")

    # 3. VLM Verification (20 pts)
    # Check if agent visited Reports section using trajectory frames
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    vlm_prompt = """
    You are verifying if an agent successfully generated a Profit and Loss Statement in Manager.io.
    Look at the sequence of screenshots.
    
    1. Did the agent navigate to the 'Reports' module? (Look for 'Reports' in sidebar or header)
    2. Did the agent view a 'Profit and Loss Statement'? (Look for report title)
    3. Did the agent set a date range (March 2024)?
    
    Return JSON:
    {
        "navigated_reports": true/false,
        "viewed_pnl": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('navigated_reports'):
            vlm_score += 10
        if parsed.get('viewed_pnl'):
            vlm_score += 10
        feedback_parts.append(f"VLM Verification: Reports={parsed.get('navigated_reports')}, P&L={parsed.get('viewed_pnl')}")
    else:
        # Fallback if VLM fails: assume innocent if file is correct
        if score >= 60:
            vlm_score = 20
            feedback_parts.append("VLM unavailable, defaulting to pass based on file content.")
    
    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }