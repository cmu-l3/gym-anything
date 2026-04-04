#!/usr/bin/env python3
"""
Verifier for deploy_strategy_on_chart task.

Criteria:
1. Workspace modified (anti-gaming).
2. Strategy 'SampleMACrossover' attached to SPY chart.
3. Parameters Fast=15, Slow=50.
4. Account = Sim101.
5. Enabled = true.
6. VLM Check: Final screenshot shows green enabled status/strategy text.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

RESULT_PATH = "C:/tmp/task_result.json"

def verify_deploy_strategy_on_chart(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
    
    # 1. Programmatic Verification (from export_result.ps1)
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        try:
            copy_from_env(RESULT_PATH, temp_path)
            with open(temp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result file: {e}"}

    score = 0
    feedback = []
    
    # Check 1: Workspace modified (Anti-gaming) (10 pts)
    if result.get("workspace_modified"):
        score += 10
        feedback.append("Workspace saved.")
    else:
        feedback.append("Workspace NOT saved (check if you saved the workspace).")

    # Check 2: Strategy Found on Instrument (30 pts)
    if result.get("strategy_found") and result.get("instrument_correct"):
        score += 30
        feedback.append("SampleMACrossover attached to SPY.")
    else:
        feedback.append("Strategy or Instrument incorrect.")

    # Check 3: Parameters (20 pts)
    if result.get("params_correct"):
        score += 20
        feedback.append("Parameters (Fast=15, Slow=50) correct.")
    else:
        feedback.append("Parameters incorrect.")

    # Check 4: Account (10 pts)
    if result.get("account_correct"):
        score += 10
        feedback.append("Account (Sim101) correct.")
    else:
        feedback.append("Account incorrect.")

    # Check 5: Enabled (10 pts)
    # This is tricky in XML (might be stale), so we rely partially on VLM too
    if result.get("enabled_correct"):
        score += 10
        feedback.append("Strategy enabled in config.")
    else:
        feedback.append("Strategy NOT enabled in config.")

    # 2. VLM Verification (20 pts)
    # Check if the strategy looks active in the UI
    final_img = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_img:
        prompt = """
        Analyze this screenshot of NinjaTrader 8.
        1. Is there a chart for SPY?
        2. Is the 'SampleMACrossover' strategy visible (e.g., text in corner, lines on chart)?
        3. Is there a visual indication that the strategy is ENABLED (e.g., green dot, green status text, 'True')?
        
        Respond with JSON: {"spy_chart": bool, "strategy_visible": bool, "is_enabled": bool}
        """
        try:
            vlm_res = query_vlm(prompt=prompt, image=final_img)
            parsed = vlm_res.get("parsed", {})
            
            if parsed.get("spy_chart") and parsed.get("strategy_visible"):
                vlm_score += 10
            
            if parsed.get("is_enabled"):
                vlm_score += 10
                
            if vlm_score > 0:
                feedback.append(f"Visual verification passed (+{vlm_score}).")
            else:
                feedback.append("Visual verification failed (strategy or enabled state not visible).")
                
        except Exception as e:
            logger.warning(f"VLM failed: {e}")
            # Fallback: if programmatic enabled check passed, give partial VLM credit
            if result.get("enabled_correct"):
                vlm_score += 10
                feedback.append("VLM failed but config confirms enabled (+10 fallback).")

    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }