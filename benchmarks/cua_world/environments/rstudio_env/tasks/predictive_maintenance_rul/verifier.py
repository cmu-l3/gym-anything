#!/usr/bin/env python3
"""
Verifier for predictive_maintenance_rul task.

Scoring (100 points total):
  1. Script Quality & Workflow (25 pts):
     - Script was modified (5 pts)
     - Implementation of rolling/lagged feature engineering (20 pts)
  
  2. Predictions CSV (20 pts):
     - CSV exists and is new (10 pts)
     - Row count is correct (approx. 100 + header) (10 pts)
  
  3. Model Performance - TRUE RMSE (25 pts):
     - Anti-gaming: Computes RMSE independently using predictions and ground truth.
     - RMSE < 40 (Excellent) = 25 pts
     - RMSE < 50 (Passable) = 15 pts
     - RMSE >= 50 or uncomputable = 0 pts

  4. Reporting Artifacts (10 pts):
     - Metrics CSV generated and new (10 pts)
  
  5. VLM Visual Check / Plot (20 pts):
     - PNG exists, is new, and has size > 15KB (10 pts)
     - VLM verification: Trajectory shows progression, scatter plot generated (10 pts)

Pass Threshold: 60 points.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/rul_task_result.json"

VERIFICATION_PROMPT = """You are evaluating an AI agent performing a predictive maintenance data science task in RStudio.
The agent was asked to build an RUL (Remaining Useful Life) regression model and plot Predicted vs Actual RUL.

Review the screenshots (trajectory frames and final screenshot) and determine:
1. Is there evidence of R script writing and execution?
2. Did the agent generate a scatter plot?
3. Does the final scatter plot show a positive correlation pattern, consistent with "Predicted vs Actual" model evaluation?

Respond in JSON format:
{
    "script_execution_visible": true/false,
    "scatter_plot_visible": true/false,
    "positive_correlation_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "Brief explanation of what is seen"
}
"""

def verify_predictive_maintenance_rul(traj, env_info, task_info):
    """Verify predictive maintenance RUL estimation task."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load export result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        except FileNotFoundError:
            return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
        except json.JSONDecodeError as e:
            return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []

    # 1. Script Quality & Workflow (25 pts)
    if result.get('script_exists') and result.get('script_is_new'):
        score += 5
        feedback.append("R Script modified (+5)")
    else:
        feedback.append("R Script missing or untouched (0/5)")

    if result.get('has_rolling_features'):
        score += 20
        feedback.append("Rolling/Lagged features implemented (+20)")
    else:
        feedback.append("No time-series feature engineering detected (0/20)")

    # 2. Predictions CSV (20 pts)
    if result.get('predictions_csv_exists') and result.get('predictions_csv_is_new'):
        score += 10
        feedback.append("Predictions CSV generated (+10)")
    else:
        feedback.append("Predictions CSV missing or not new (0/10)")

    row_count = result.get('predictions_row_count', 0)
    # Expect 100 test engines + 1 header = 101 rows (allow slight variance if formatting differs)
    if 95 <= row_count <= 105:
        score += 10
        feedback.append(f"Predictions CSV has correct row count: {row_count} (+10)")
    else:
        feedback.append(f"Predictions CSV has incorrect row count: {row_count}. Expected ~101 (0/10)")

    # 3. Model Performance - TRUE RMSE (25 pts)
    true_rmse = result.get('true_rmse', -1)
    if true_rmse != -1:
        if true_rmse < 40:
            score += 25
            feedback.append(f"Excellent Model Performance: True RMSE = {true_rmse:.2f} < 40 (+25)")
        elif true_rmse < 55:
            score += 15
            feedback.append(f"Passable Model Performance: True RMSE = {true_rmse:.2f} < 55 (+15)")
        else:
            feedback.append(f"Poor Model Performance: True RMSE = {true_rmse:.2f} (0/25)")
    else:
        feedback.append("True RMSE could not be calculated (Predictions missing or misaligned) (0/25)")

    # 4. Reporting Artifacts (10 pts)
    if result.get('metrics_csv_exists') and result.get('metrics_csv_is_new'):
        score += 10
        feedback.append("Metrics CSV generated (+10)")
    else:
        feedback.append("Metrics CSV missing (0/10)")

    # 5. VLM Visual Check / Plot (20 pts)
    vlm_score = 0
    if result.get('plot_png_exists') and result.get('plot_png_is_new') and result.get('plot_size_kb', 0) > 15:
        vlm_score += 10
        feedback.append("Performance plot PNG generated and has valid size (+10)")
    else:
        feedback.append("Performance plot PNG missing or too small (0/10)")

    # Run VLM Verification
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            try:
                vlm_resp = query_vlm(prompt=VERIFICATION_PROMPT, images=images)
                if vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    if parsed.get("scatter_plot_visible"):
                        vlm_score += 5
                        feedback.append("VLM confirmed scatter plot (+5)")
                    if parsed.get("positive_correlation_visible"):
                        vlm_score += 5
                        feedback.append("VLM confirmed correlation in plot (+5)")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                feedback.append("VLM check failed, skipping visual verification.")
    
    score += vlm_score

    # Determine Pass/Fail
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "true_rmse": true_rmse,
            "vlm_score": vlm_score
        }
    }