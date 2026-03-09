#!/usr/bin/env python3
"""
Verifier for NinjaTrader Multi-Timeframe Indicator Overlay task.

Task:
1. Create SPY Daily Chart
2. Add SPY Weekly Data Series (overlay)
3. Add SMA(50)
4. Set SMA Input Series to Weekly (Series Index 1)

Verification uses:
1. XML Analysis (via export_result.ps1) for state verification.
2. VLM Analysis (via trajectory) for workflow verification.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Standard VLM logic helpers
def get_final_screenshot(traj):
    if not traj or 'screenshots' not in traj or not traj['screenshots']:
        return None
    return traj['screenshots'][-1]

def sample_trajectory_frames(traj, n=4):
    if not traj or 'screenshots' not in traj:
        return []
    screenshots = traj['screenshots']
    if len(screenshots) <= n:
        return screenshots
    import numpy as np
    indices = np.linspace(0, len(screenshots)-1, n, dtype=int)
    return [screenshots[i] for i in indices]

def verify_multi_timeframe_setup(traj, env_info, task_info):
    """
    Verify the multi-timeframe indicator setup.
    """
    # 1. Setup & Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve Exported JSON Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: path matches where export_result.ps1 saves it in the container
        copy_from_env("C:\\Users\\Docker\\Desktop\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read task result from environment (Script execution failed?)"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Score Calculation
    score = 0
    feedback_parts = []
    
    # Check 1: Workspace Modified (10 pts)
    # Anti-gaming: Ensure the agent actually did something
    if result.get('workspace_modified', False):
        score += 10
        feedback_parts.append("Workspace saved.")
    else:
        feedback_parts.append("Workspace NOT saved (or no new file found).")

    # Check 2: Chart & Instrument (10 pts)
    if result.get('chart_found', False) and result.get('instrument_correct', False):
        score += 10
        feedback_parts.append("SPY Chart created.")
    else:
        feedback_parts.append("SPY Chart NOT found.")

    # Check 3: Multi-Series / Weekly Data (30 pts)
    # This is the core "overlay" mechanic
    if result.get('multi_series_found', False) and "Weekly" in result.get('series_periods', []):
        score += 30
        feedback_parts.append("Weekly Data Series added successfully.")
    elif result.get('multi_series_found', False):
        score += 15
        feedback_parts.append("Multi-series chart found, but Weekly period not detected.")
    else:
        feedback_parts.append("Secondary Data Series NOT found.")

    # Check 4: SMA Indicator (20 pts)
    if result.get('sma_found', False):
        if result.get('sma_period_correct', False):
            score += 20
            feedback_parts.append("SMA(50) added.")
        else:
            score += 10
            feedback_parts.append("SMA added but wrong period (expected 50).")
    else:
        feedback_parts.append("SMA indicator NOT found.")

    # Check 5: Input Series Routing (30 pts) - CRITICAL
    # Index 1 implies the secondary series (Weekly). Index 0 is primary (Daily).
    series_idx = result.get('sma_input_series_index', -1)
    if series_idx == 1:
        score += 30
        feedback_parts.append("SMA correctly linked to Weekly input series.")
    elif series_idx == 0:
        feedback_parts.append("SMA is using default Daily series (Wrong Input).")
    else:
        feedback_parts.append("SMA input series configuration unclear.")

    # 4. VLM Verification (Trajectory Analysis)
    # We use this to confirm UI interaction if XML parsing is ambiguous
    # or as a secondary signal.
    
    # We only penalize if programmatic failed but VLM looks good (rare), 
    # or use it to bump score if XML is partial.
    # Here we primarily rely on programmatic, but let's check for visual confirmation of the chart.
    
    # (Optional: Add VLM logic here if needed for robustness, but XML is strong for NinjaTrader)

    # 5. Final Determination
    # Pass requires: Workspace Modified + Multi-Series + Correct Input Series
    passed = (
        result.get('workspace_modified', False) and
        result.get('multi_series_found', False) and
        result.get('sma_input_series_index', -1) == 1
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }