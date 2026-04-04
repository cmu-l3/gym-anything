#!/usr/bin/env python3
"""
Verifier for setup_heiken_ashi_trend_chart task.

SCORING CRITERIA:
1. Workspace saved (modified during task): 15 pts
2. SPY instrument present: 15 pts
3. Heiken Ashi bar type configured: 25 pts
4. ADX(14) indicator present: 20 pts
5. Parabolic SAR(0.02, 0.2) present: 20 pts
6. VLM Visual Verification (Heiken Ashi style + Indicators): 5 pts (Bonus/Confirmation)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Windows path inside container
CONTAINER_RESULT_PATH = "C:\\Users\\Docker\\Desktop\\task_result.json"

def verify_setup_heiken_ashi_trend_chart(traj, env_info, task_info):
    """
    Verify the NinjaTrader Heiken Ashi chart setup.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 1. Load Programmatic Results
    result = {}
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        # Copy result from Windows container
        copy_from_env(CONTAINER_RESULT_PATH, temp_path)
        
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
            
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Could not read verification results from container (Export script may have failed)."
        }
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    # 2. Scoring Logic
    score = 0
    feedback = []

    # Check 1: Workspace Saved (15 pts)
    if result.get('workspace_saved', False):
        score += 15
        feedback.append("Workspace saved.")
    else:
        feedback.append("Workspace NOT saved (or no modification detected).")

    # Check 2: SPY Instrument (15 pts)
    if result.get('spy_present', False):
        score += 15
        feedback.append("SPY instrument found.")
    else:
        feedback.append("SPY instrument missing.")

    # Check 3: Heiken Ashi (25 pts)
    if result.get('heiken_ashi_present', False):
        score += 25
        feedback.append("Heiken Ashi bar type confirmed.")
    else:
        feedback.append("Heiken Ashi bar type NOT found.")

    # Check 4: ADX (20 pts)
    if result.get('adx_present', False):
        score += 20
        feedback.append("ADX(14) indicator confirmed.")
    else:
        feedback.append("ADX(14) indicator missing or wrong parameters.")

    # Check 5: Parabolic SAR (20 pts)
    if result.get('parabolic_sar_present', False):
        score += 20
        feedback.append("Parabolic SAR confirmed.")
    else:
        feedback.append("Parabolic SAR missing or wrong parameters.")

    # 3. VLM Verification (Visual Check - 5 pts)
    # We verify if the chart actually looks like Heiken Ashi (smooth bars) and has dots (PSAR)
    try:
        final_img = get_final_screenshot(traj)
        if final_img:
            vlm_prompt = """
            Analyze this NinjaTrader chart.
            1. Are the price bars Heiken Ashi style? (Typically uniform color trends, flat bottoms/tops on trends, distinct from standard candles).
            2. Are there dots above/below the price bars (Parabolic SAR)?
            3. Is there a sub-panel with a line indicator (ADX)?
            4. Is the instrument SPY?
            Return JSON: {"is_heiken_ashi": bool, "has_dots": bool, "has_subpanel": bool}
            """
            
            # This is a soft check, we add points if it confirms
            vlm_res = query_vlm(image=final_img, prompt=vlm_prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('is_heiken_ashi') or parsed.get('has_dots'):
                    score += 5
                    feedback.append("Visual verification passed.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    # Cap score at 100
    score = min(100, score)

    # Pass Threshold
    # Must have at least SPY + Heiken Ashi to consider "passing" main objective
    key_requirements = result.get('spy_present') and result.get('heiken_ashi_present')
    passed = (score >= 70) and key_requirements

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }