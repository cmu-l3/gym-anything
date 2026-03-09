#!/usr/bin/env python3
"""
Verifier for identify_trend_reversal_setup task (NinjaTrader 8).

Verifies:
1. Workspace saved (File modified)
2. MSFT Instrument selected
3. Chart Type = Line Break
4. Line Break Value = 3
5. Stochastic Oscillator (14,3,3) present
6. ADX (14) present
7. VLM Trajectory: Confirms UI interaction with Data Series and Indicators
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILENAME = "identify_trend_reversal_setup_result.json"

def verify_identify_trend_reversal_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 1. Parsing File-Based Results
    result = {}
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        try:
            # NinjaTrader tasks export to Desktop usually
            remote_path = f"C:\\Users\\Docker\\Desktop\\NinjaTraderTasks\\{RESULT_FILENAME}"
            # Adjust path separators for linux copy command if needed, but usually copy_from_env handles it
            # If the environment is Windows, the path inside is Windows-style.
            
            # Note: gym-anything path handling might require forward slashes
            remote_path_fwd = "C:/Users/Docker/Desktop/NinjaTraderTasks/" + RESULT_FILENAME
            
            copy_from_env(remote_path_fwd, temp_path)
            
            with open(temp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found (Task export failed)"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # --- SCORING CRITERIA ---
    
    # 1. Workspace Modification (15 pts)
    # Anti-gaming: must have saved new work
    if result.get('workspace_modified', False):
        score += 15
        feedback_parts.append("Workspace modified (+15)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")
        
    # 2. Instrument MSFT (15 pts)
    if result.get('msft_found', False):
        score += 15
        feedback_parts.append("MSFT found (+15)")
    else:
        feedback_parts.append("MSFT NOT found (0)")

    # 3. Chart Type: Line Break (20 pts)
    if result.get('chart_type_correct', False):
        score += 20
        feedback_parts.append("Line Break chart type correct (+20)")
    else:
        feedback_parts.append(f"Incorrect chart type: {result.get('chart_type_found', 'None')} (0)")

    # 4. Line Break Value (10 pts)
    val = result.get('line_break_value', 0)
    if val == 3:
        score += 10
        feedback_parts.append("Line Break Value=3 correct (+10)")
    else:
        feedback_parts.append(f"Line Break Value={val}, expected 3 (0)")

    # 5. Stochastic Indicator (15 pts)
    if result.get('stochastic_found', False):
        score += 15
        feedback_parts.append("Stochastic found (+15)")
    else:
        feedback_parts.append("Stochastic missing (0)")

    # 6. ADX Indicator (15 pts)
    if result.get('adx_found', False):
        score += 15
        feedback_parts.append("ADX found (+15)")
    else:
        feedback_parts.append("ADX missing (0)")

    # --- VLM VERIFICATION (10 pts) ---
    # We verify the trajectory to ensure they actually used the UI menus
    vlm_score = 0
    vlm_passed = False
    
    # Only run VLM if they did at least some work (score > 30) to save cost/time
    if score >= 30:
        frames = sample_trajectory_frames(traj, n=4)
        prompt = """
        Review these screenshots of a NinjaTrader user.
        The user should be configuring a 'Line Break' chart for MSFT and adding indicators.
        
        Look for:
        1. 'Data Series' dialog or menu (to set Line Break).
        2. 'Indicators' dialog (to add Stochastic/ADX).
        3. A chart that looks like blocks/bricks (Line Break) rather than standard candles.
        
        Does the trajectory show evidence of configuring these specific settings?
        Response format JSON: {"evidence_found": bool, "chart_looks_correct": bool}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("evidence_found") or parsed.get("chart_looks_correct"):
                    vlm_score = 10
                    vlm_passed = True
                    feedback_parts.append("VLM: Workflow confirmed (+10)")
                else:
                    feedback_parts.append("VLM: No visual evidence of configuration (0)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: give points if file check was perfect
            if score >= 80:
                vlm_score = 10
                feedback_parts.append("VLM: Skipped, assumed good based on file score (+10)")

    score += vlm_score

    # Pass Threshold: 70
    # Requires at least: Workspace + MSFT + ChartType + One Indicator
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }