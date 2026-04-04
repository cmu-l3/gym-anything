#!/usr/bin/env python3
"""
Verifier for configure_chart_trader_order_entry task.

Multi-signal verification:
1. Workspace XML analysis (Primary) - Checks if settings were saved to disk.
2. VLM Trajectory Verification (Secondary) - Checks if panel was actually visible during interaction.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_chart_trader(traj, env_info, task_info):
    """
    Verify that Chart Trader is configured correctly on a SPY chart.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result file (workspace may not have been saved)"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Programmatic Scoring (XML) ---
    
    # 1. Workspace Saved (15 pts)
    if result.get('workspace_modified', False):
        score += 15
        feedback.append("Workspace saved (+15)")
    else:
        feedback.append("Workspace NOT saved (0)")
        
    # 2. SPY Chart Exists (15 pts)
    if result.get('instrument_found', False):
        score += 15
        feedback.append("SPY chart configured (+15)")
    else:
        feedback.append("SPY chart not found in saved workspace (0)")

    # 3. Chart Trader Enabled (25 pts)
    if result.get('chart_trader_enabled', False):
        score += 25
        feedback.append("Chart Trader panel enabled (+25)")
    else:
        feedback.append("Chart Trader panel configuration not found (0)")

    # 4. Account Sim101 (15 pts)
    if result.get('account_correct', False):
        score += 15
        feedback.append("Account set to Sim101 (+15)")
    else:
        feedback.append("Account incorrect or not set to Sim101 (0)")
        
    # 5. Quantity 200 (10 pts)
    if result.get('quantity_correct', False):
        score += 10
        feedback.append("Default quantity set to 200 (+10)")
    else:
        feedback.append("Default quantity incorrect (0)")
        
    # 6. SMA Indicator (10 pts)
    if result.get('indicator_found', False):
        score += 10
        feedback.append("SMA(20) indicator added (+10)")
    else:
        feedback.append("SMA indicator missing or wrong period (0)")

    # --- VLM Verification (Visual Confirmation) ---
    # We check the final screenshot or trajectory to ensure the panel is actually visible
    # This catches cases where XML might have 'enabled=true' but panel is hidden/collapsed
    
    vlm_score = 0
    vlm_feedback = ""
    
    final_img = get_final_screenshot(traj)
    if final_img:
        prompt = """
        Analyze this screenshot of NinjaTrader 8.
        1. Is a chart visible for SPY?
        2. Is the "Chart Trader" panel visible on the side of the chart? (It typically has Buy/Sell buttons, quantity field, etc.)
        3. Can you see a quantity of "200"?
        4. Can you see an SMA line (a smooth curve overlaying the price bars)?
        
        Return JSON:
        {
            "chart_visible": bool,
            "chart_trader_panel_visible": bool,
            "quantity_200_visible": bool,
            "sma_visible": bool
        }
        """
        try:
            vlm_res = query_vlm(prompt=prompt, image=final_img)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('chart_trader_panel_visible'):
                    vlm_score += 10
                    vlm_feedback = "VLM confirmed Chart Trader panel visibility (+10)"
                else:
                    vlm_feedback = "VLM could not verify Chart Trader panel visibility"
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
    
    score += vlm_score
    if vlm_feedback:
        feedback.append(vlm_feedback)
    
    # Calculate Final
    passed = (score >= 70) and result.get('chart_trader_enabled', False)
    
    return {
        "passed": passed,
        "score": min(100, score), # Cap at 100 just in case
        "feedback": " | ".join(feedback)
    }