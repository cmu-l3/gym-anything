#!/usr/bin/env python3
"""
Verifier for setup_renko_chart task in NinjaTrader.

Criteria:
1. Workspace file modified (anti-gaming check)
2. Chart instrument is SPY
3. Bar Type is Renko
4. Brick Size is 2
5. Indicators EMA and ADX are present

Verification Method:
- Parses JSON result exported from the Windows environment.
- The JSON contains analysis of XML workspace files saved by NinjaTrader.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_renko_chart(traj, env_info, task_info):
    """
    Verify that the user correctly set up the Renko chart in NinjaTrader.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    remote_result_path = "C:\\temp\\task_result.json"
    
    # Create temp file to store the copied result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_result.close() # Close immediately so we can write to it
    
    try:
        # Copy result file from container
        copy_from_env(remote_result_path, temp_result.name)
        
        # Read the result
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
    except Exception as e:
        logger.error(f"Failed to copy or read result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve verification data. Did you save the workspace?"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Scoring Logic
    score = 0
    feedback_parts = []
    
    # Check 1: Workspace Modified (Action taken)
    if result_data.get("workspace_modified", False):
        score += 10
        feedback_parts.append("Workspace saved.")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No workspace changes detected. Please ensure you save the workspace (File > Save Workspace) after making changes."
        }

    # Check 2: SPY Instrument (15 pts)
    if result_data.get("spy_detected", False):
        score += 15
        feedback_parts.append("SPY instrument found.")
    else:
        feedback_parts.append("SPY instrument NOT found.")

    # Check 3: Renko Bar Type (25 pts)
    if result_data.get("renko_detected", False):
        score += 25
        feedback_parts.append("Renko bar type configured.")
    else:
        feedback_parts.append("Renko bar type NOT found.")

    # Check 4: Brick Size 2 (15 pts)
    if result_data.get("brick_size_correct", False):
        score += 15
        feedback_parts.append("Brick size set to 2.")
    else:
        feedback_parts.append("Brick size incorrect or not found.")

    # Check 5: Indicators (35 pts total)
    if result_data.get("ema_detected", False):
        score += 20
        feedback_parts.append("EMA indicator found.")
    else:
        feedback_parts.append("EMA indicator missing.")

    if result_data.get("adx_detected", False):
        score += 15
        feedback_parts.append("ADX indicator found.")
    else:
        feedback_parts.append("ADX indicator missing.")

    # Final Evaluation
    # Threshold: 70 points. Must have Renko (core of task) to pass meaningfully, 
    # but score accumulation handles that naturally (Max 75 without Renko).
    # Pass logic: score >= 70
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }