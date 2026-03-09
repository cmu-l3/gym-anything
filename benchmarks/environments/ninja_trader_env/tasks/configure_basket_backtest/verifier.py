#!/usr/bin/env python3
"""
Verifier for NinjaTrader configure_basket_backtest task.

SCORING CRITERIA:
1. Workspace Modified (15 pts): Agent saved the workspace during the task.
2. Strategy Analyzer Present (15 pts): Workspace contains Strategy Analyzer config.
3. Correct Strategy (15 pts): 'SampleMACrossover' selected.
4. Basket Instruments (25 pts): SPY, AAPL, MSFT all present (8.33 pts each).
5. Date Range (10 pts): Configuration reflects 2024 dates.
6. VLM Verification (20 pts): Visual confirmation of backtest results/setup.

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_basket_backtest(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Helper to load JSON result
    def load_result_json():
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            # Note: Path must match what is in export_result.ps1
            copy_from_env("C:\\Users\\Docker\\Desktop\\task_result.json", temp.name)
            with open(temp.name, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load result JSON: {e}")
            return {}
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)

    result_data = load_result_json()
    logger.info(f"Task Result Data: {result_data}")

    score = 0
    feedback = []

    # 1. Workspace Modified (15 pts)
    if result_data.get("workspace_modified", False):
        score += 15
        feedback.append("Workspace saved successfully.")
    else:
        feedback.append("Workspace was not saved (or no changes detected).")

    # 2. Strategy Analyzer Present (15 pts)
    if result_data.get("found_strategy_window", False):
        score += 15
        feedback.append("Strategy Analyzer window found in workspace.")
    else:
        feedback.append("No Strategy Analyzer found in workspace.")

    # 3. Correct Strategy (15 pts)
    # The export script looks for "SampleMACrossover" or "MACrossover"
    if result_data.get("found_strategy_name", False):
        score += 15
        feedback.append("Correct strategy (SampleMACrossover) selected.")
    else:
        feedback.append("SampleMACrossover strategy not detected in configuration.")

    # 4. Basket Instruments (25 pts)
    found_instruments = set(result_data.get("found_instruments", []))
    required_instruments = {"SPY", "AAPL", "MSFT"}
    
    # Calculate overlap
    matched = found_instruments.intersection(required_instruments)
    inst_score = int((len(matched) / 3) * 25)
    score += inst_score
    
    if len(matched) == 3:
        feedback.append("All 3 instruments (SPY, AAPL, MSFT) found in basket.")
    elif len(matched) > 0:
        feedback.append(f"Found {len(matched)}/3 instruments: {', '.join(matched)}.")
    else:
        feedback.append("No required instruments found in basket configuration.")

    # 5. Date Range (10 pts)
    if result_data.get("found_dates", False):
        score += 10
        feedback.append("Date range configuration detected.")
    else:
        feedback.append("Date range (2024) not explicitly detected in workspace file.")

    # 6. VLM Verification (20 pts)
    # We look for the Strategy Analyzer window and potential backtest results (stats grid, equity curve)
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if frames and final_frame:
        prompt = """
        Analyze these screenshots of NinjaTrader 8.
        The user is supposed to:
        1. Open the "Strategy Analyzer" window.
        2. Configure a backtest for SPY, AAPL, and MSFT.
        3. Run the backtest.
        
        Look for:
        - A window titled "Strategy Analyzer".
        - A list of instruments (SPY, AAPL, MSFT) or a 'Basket' selection.
        - Backtest results (Performance statistics like 'Total Net Profit', a trade list, or an equity chart).
        
        Return JSON:
        {
            "strategy_analyzer_visible": boolean,
            "backtest_results_visible": boolean,
            "instruments_visible": boolean,
            "confidence": "high/medium/low"
        }
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final_frame], prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                
                if parsed.get('strategy_analyzer_visible'):
                    vlm_score += 10
                    feedback.append("VLM: Strategy Analyzer window visible.")
                
                if parsed.get('backtest_results_visible'):
                    vlm_score += 10
                    feedback.append("VLM: Backtest results visible.")
                elif parsed.get('instruments_visible'):
                    vlm_score += 5
                    feedback.append("VLM: Instruments selection visible.")
                    
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback.append("VLM verification failed to run.")

    score += vlm_score

    # Final Pass Logic
    # Must have saved workspace, correct strategy, and at least 2 instruments
    key_requirements = (
        result_data.get("workspace_modified") and
        result_data.get("found_strategy_name") and
        len(matched) >= 2
    )
    
    passed = (score >= 70) and key_requirements

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }