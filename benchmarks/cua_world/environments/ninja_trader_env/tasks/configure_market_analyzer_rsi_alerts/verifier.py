#!/usr/bin/env python3
"""
Verifier for NinjaTrader Market Analyzer RSI Alerts task.

Scoring Breakdown:
- Market Analyzer Created (20 pts)
- Instruments Correct (20 pts) - must have SPY, AAPL, MSFT
- RSI Column Added (20 pts)
- Overbought Condition (>70) (20 pts)
- Oversold Condition (<30) (20 pts)

Pass Threshold: 80 points
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_configure_market_analyzer_rsi_alerts(traj, env_info, task_info):
    """
    Verifies that the Market Analyzer was created with correct instruments, RSI column, and conditions.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. File-based verification (Primary)
    file_score = 0
    feedback_parts = []
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
            
        # Clean up
        os.unlink(temp_file.name)
        
        # Check criteria
        if result.get('market_analyzer_found'):
            file_score += 20
            feedback_parts.append("Market Analyzer created (+20)")
        else:
            feedback_parts.append("Market Analyzer NOT found")

        inst_count = result.get('instruments_count', 0)
        if inst_count >= 3:
            file_score += 20
            feedback_parts.append("All 3 instruments found (+20)")
        elif inst_count > 0:
            file_score += 10
            feedback_parts.append(f"Partial instruments ({inst_count}/3) (+10)")
        else:
            feedback_parts.append("No correct instruments found")

        if result.get('rsi_column_found'):
            file_score += 20
            feedback_parts.append("RSI column found (+20)")
        else:
            feedback_parts.append("RSI column NOT found")

        if result.get('condition_overbought_found'):
            file_score += 20
            feedback_parts.append("Overbought condition (>70) found (+20)")
        else:
            feedback_parts.append("Overbought condition missing")

        if result.get('condition_oversold_found'):
            file_score += 20
            feedback_parts.append("Oversold condition (<30) found (+20)")
        else:
            feedback_parts.append("Oversold condition missing")
            
    except Exception as e:
        logger.error(f"Error reading result file: {e}")
        feedback_parts.append(f"Verification error: {str(e)}")
        # Fallback to 0 if file reading fails
    
    # 2. VLM Verification (Secondary/Safety)
    # If file score is high, we just do a sanity check. If low, VLM won't save it (XML is truth).
    # But we use VLM to confirm the visual state for the trajectory.
    
    vlm_score = 0
    if file_score >= 60:
        # Check if the final screenshot actually shows the market analyzer
        # This prevents cases where XML is hacked but UI is empty (unlikely but possible)
        final_screen = get_final_screenshot(traj)
        if final_screen:
            prompt = """
            Look at the screenshot of NinjaTrader 8.
            Is there a 'Market Analyzer' window visible?
            Does it list tickers like SPY, AAPL, or MSFT?
            Do you see a column labeled 'RSI'?
            Are there any colored cells (Red or Green) in the RSI column?
            
            Return JSON:
            {
                "market_analyzer_visible": true/false,
                "rsi_column_visible": true/false,
                "colored_cells_visible": true/false
            }
            """
            vlm_res = query_vlm(prompt=prompt, image=final_screen)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if not parsed.get('market_analyzer_visible'):
                    feedback_parts.append("WARNING: VLM could not see Market Analyzer window")
                    # We don't deduct points heavily if XML confirmed it, but it's a flag
                else:
                    feedback_parts.append("VLM confirms visual state")

    total_score = file_score
    passed = total_score >= 80

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }