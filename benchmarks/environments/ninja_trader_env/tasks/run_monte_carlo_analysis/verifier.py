#!/usr/bin/env python3
"""
Verifier for run_monte_carlo_analysis task.

Task: Run a Monte Carlo simulation (1000 iterations) on SampleMACrossover backtest for SPY.

Verification Strategy:
1. Workspace File Analysis (Primary):
   - Check if workspace was modified after task start.
   - Parse XML for Strategy Analyzer, Strategy, Instrument, and Monte Carlo settings.
2. VLM Verification (Secondary):
   - Check trajectory for visual confirmation of the workflow.

Scoring (100 points):
- Workspace Modified: 15 pts
- Strategy Analyzer Present: 20 pts
- Correct Strategy (SampleMACrossover): 15 pts
- Correct Instrument (SPY): 15 pts
- Monte Carlo Configured: 20 pts
- Iterations = 1000: 15 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_REMOTE_PATH = r"C:\Users\Docker\Desktop\NinjaTraderTasks\run_monte_carlo_analysis_result.json"

def verify_run_monte_carlo_analysis(traj, env_info, task_info):
    """
    Verify that the Monte Carlo analysis was performed and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_REMOTE_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve verification data from environment. Did the export script run?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    feedback_parts = []
    
    # Criterion 1: Workspace Modified (15 pts)
    if result.get("workspace_modified", False):
        score += 15
        feedback_parts.append("Workspace saved (+15)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")

    # Criterion 2: Strategy Analyzer Present (20 pts)
    if result.get("has_strategy_analyzer", False):
        score += 20
        feedback_parts.append("Strategy Analyzer found (+20)")
    else:
        feedback_parts.append("Strategy Analyzer NOT found (0)")

    # Criterion 3: Correct Strategy (15 pts)
    if result.get("has_sample_ma_crossover", False):
        score += 15
        feedback_parts.append("Correct Strategy (+15)")
    else:
        feedback_parts.append("Wrong/Missing Strategy (0)")

    # Criterion 4: Correct Instrument (15 pts)
    if result.get("has_spy", False):
        score += 15
        feedback_parts.append("Correct Instrument (+15)")
    else:
        feedback_parts.append("Wrong/Missing Instrument (0)")

    # Criterion 5: Monte Carlo Configured (20 pts)
    if result.get("has_monte_carlo", False):
        score += 20
        feedback_parts.append("Monte Carlo analysis found (+20)")
    else:
        feedback_parts.append("Monte Carlo NOT found (0)")

    # Criterion 6: Iterations Correct (15 pts)
    # We allow VLM to rescue this point if XML parsing fails but visual is clear
    xml_iterations_ok = result.get("has_1000_iterations", False)
    
    if xml_iterations_ok:
        score += 15
        feedback_parts.append("1,000 Iterations confirmed (+15)")
    else:
        # Fallback to VLM for iteration count if needed
        feedback_parts.append("1,000 Iterations check failed in XML")

    # 3. VLM Verification (for anti-gaming and robustness)
    # If score is borderline or high, verify visually to confirm it's not just a saved empty file
    if score >= 50:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = """
        Analyze these screenshots of NinjaTrader 8.
        The user should be running a Monte Carlo simulation in the Strategy Analyzer.
        
        Look for:
        1. A 'Strategy Analyzer' window.
        2. A 'Monte Carlo' tab or section visible.
        3. A results chart (often lines or distribution curves) indicating a simulation ran.
        4. The number '1000' in an 'Iterations' or 'Simulations' field.
        
        Return JSON:
        {
            "strategy_analyzer_visible": true/false,
            "monte_carlo_results_visible": true/false,
            "iterations_visible": true/false
        }
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                
                # Bonus or validation
                if parsed.get("monte_carlo_results_visible"):
                    feedback_parts.append("[VLM] Visual confirmation of results")
                else:
                    feedback_parts.append("[VLM] Warning: Results not clearly visible")
                    
                # Rescue iterations points if VLM sees them but XML didn't
                if not xml_iterations_ok and parsed.get("iterations_visible"):
                    score += 15
                    feedback_parts.append("[VLM] 1,000 Iterations visually confirmed (+15)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Pass logic
    passed = (score >= 70) and result.get("has_strategy_analyzer", False)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }