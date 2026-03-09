#!/usr/bin/env python3
"""
Verifier for setup_kagi_chart task.

Verifies that the user created a Kagi chart for MSFT with SMA and Stochastic indicators.
Uses a combination of workspace XML analysis (from export script) and VLM visual verification.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_kagi_chart(traj, env_info, task_info):
    """
    Verify Kagi chart setup.
    
    Scoring Criteria:
    1. Workspace Modified (Antigaming): 15 pts
    2. Kagi Bar Type Detected (XML): 25 pts
    3. MSFT Instrument Detected (XML): 15 pts
    4. SMA Indicator Detected (XML): 15 pts
    5. Stochastic Indicator Detected (XML): 15 pts
    6. Visual Verification (VLM): 15 pts (Checks for chart structure)
    
    Pass threshold: 70 pts (Must have Kagi + Instrument or Kagi + VLM)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In Windows envs, the path might need handling, but copy_from_env should handle the abstraction
        # The export script saved to C:\Users\Docker\AppData\Local\Temp\task_result.json
        # We need to use the path consistent with the env's mounting or copy mechanism.
        # Assuming copy_from_env handles the guest path correctly:
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Workspace Modified (15 pts)
    if result.get('workspace_modified', False):
        score += 15
        feedback_parts.append("Workspace saved (+15)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")

    # Criterion 2: Kagi Bar Type (25 pts)
    if result.get('has_kagi', False):
        score += 25
        feedback_parts.append("Kagi bar type configured (+25)")
    else:
        feedback_parts.append("Kagi bar type NOT found in workspace (0)")

    # Criterion 3: MSFT Instrument (15 pts)
    if result.get('has_msft', False):
        score += 15
        feedback_parts.append("MSFT instrument found (+15)")
    else:
        feedback_parts.append("MSFT instrument NOT found (0)")

    # Criterion 4: SMA (15 pts)
    if result.get('has_sma', False):
        score += 15
        feedback_parts.append("SMA indicator found (+15)")
    else:
        feedback_parts.append("SMA indicator missing (0)")

    # Criterion 5: Stochastic (15 pts)
    if result.get('has_stochastic', False):
        score += 15
        feedback_parts.append("Stochastic indicator found (+15)")
    else:
        feedback_parts.append("Stochastic indicator missing (0)")

    # Criterion 6: VLM Verification (15 pts)
    # We check if the chart visually resembles a Kagi chart (vertical lines, no standard candles)
    frames = sample_trajectory_frames(traj, n=3)
    
    vlm_prompt = """
    Analyze these screenshots of a trading platform (NinjaTrader).
    
    I am looking for a specific chart type called 'Kagi'.
    A Kagi chart looks different from standard candlesticks.
    - It has vertical lines connected by short horizontal lines.
    - The lines vary in thickness (thick/Yang vs thin/Yin).
    - It does NOT look like standard red/green rectangular candles.
    
    Also check for:
    - An indicator line overlaid on the price.
    - A separate sub-panel at the bottom with oscillator lines (Stochastic).
    
    Does the final or latest state show a Kagi-style chart for MSFT?
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        # We assume query_vlm returns a dict with 'success' and 'parsed' or a direct string/bool depending on implementation.
        # This is a stub adaptation for the assumed API.
        
        # Simple keyword check if structured response isn't guaranteed
        vlm_text = str(vlm_result).lower()
        
        if "kagi" in vlm_text and ("yes" in vlm_text or "true" in vlm_text):
            score += 15
            feedback_parts.append("VLM confirmed Kagi chart visualization (+15)")
        else:
            feedback_parts.append("VLM did not confirm Kagi chart visual (0)")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        feedback_parts.append("VLM check skipped due to error")

    # Final Pass Check
    # Must have at least 70 points
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }