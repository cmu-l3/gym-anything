#!/usr/bin/env python3
"""
Verifier for setup_comparative_percentage_chart task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_comparative_percentage_chart(traj, env_info, task_info):
    """
    Verifies that the agent configured a comparative percentage chart with SPY, AAPL, MSFT.
    
    Scoring Criteria:
    1. Workspace modified (10 pts)
    2. All instruments present (30 pts)
    3. Percentage axis configured (30 pts)
    4. Overlay configuration (all on same panel) (20 pts)
    5. Date range correct (10 pts)
    
    VLM Validation (Secondary Check):
    - Confirms visual presence of 3 lines and % axis if file check is ambiguous.
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. File-based Verification
    file_score = 0
    feedback_parts = []
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result file"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Logic
    
    # Criterion 1: Workspace Modified (10 pts)
    if result_data.get('workspace_modified', False):
        file_score += 10
        feedback_parts.append("Workspace saved.")
    else:
        feedback_parts.append("Workspace NOT saved or modified.")

    # Criterion 2: Instruments (30 pts)
    found_instr = result_data.get('instruments_found', [])
    required_instr = {'SPY', 'AAPL', 'MSFT'}
    found_set = set(instr.upper() for instr in found_instr)
    
    matches = len(required_instr.intersection(found_set))
    if matches == 3:
        file_score += 30
        feedback_parts.append("All instruments (SPY, AAPL, MSFT) found.")
    else:
        file_score += (matches * 10)
        feedback_parts.append(f"Found {matches}/3 instruments: {list(found_set)}")

    # Criterion 3: Percentage Axis (30 pts)
    if result_data.get('percentage_axis_found', False):
        file_score += 30
        feedback_parts.append("Percentage axis configured.")
    else:
        feedback_parts.append("Percentage axis NOT detected in XML.")

    # Criterion 4: Overlay (20 pts)
    if result_data.get('overlay_mode_correct', False):
        file_score += 20
        feedback_parts.append("Overlay configuration correct (single panel).")
    else:
        feedback_parts.append("Overlay configuration incorrect (multiple panels detected).")

    # Criterion 5: Date Range (10 pts)
    if result_data.get('date_range_correct', False):
        file_score += 10
        feedback_parts.append("Date range (2023) correct.")
    else:
        feedback_parts.append("Date range could not be verified.")

    # 2. VLM Verification (Validation wrapper)
    # If we are close to passing but missing file signals (e.g. XML parsing failed), use VLM
    # Or use VLM to confirm the chart actually looks right.
    
    final_screenshot = get_final_screenshot(traj)
    vlm_confirmed = False
    
    if final_screenshot:
        prompt = """
        Analyze this NinjaTrader chart.
        1. Are there three distinct data lines (price series) visible on the main chart?
        2. Does the vertical axis (Y-axis) show percentage signs (%) or numbers indicating percentage return (e.g., small numbers like 10, 20, 50, not price levels like 150, 400)?
        3. Do the lines start from a common point on the left side (normalized)?
        
        Reply with JSON: {"three_lines": bool, "percent_axis": bool, "normalized_start": bool}
        """
        try:
            vlm_res = query_vlm(image=final_screenshot, prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('percent_axis') and parsed.get('three_lines'):
                vlm_confirmed = True
                if not result_data.get('percentage_axis_found'):
                    feedback_parts.append("VLM confirmed Percentage Axis (override XML check).")
                    file_score = min(100, file_score + 30) # Grant points if XML missed it
        except Exception:
            pass

    # Final tally
    passed = file_score >= 70
    
    return {
        "passed": passed,
        "score": file_score,
        "feedback": " | ".join(feedback_parts)
    }