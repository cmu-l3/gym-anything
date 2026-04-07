#!/usr/bin/env python3
"""
Verifier for create_line_forecast task in Oracle Analytics Desktop.

Verification Strategy:
1. File Check: Confirm 'Supply_Chain_Forecast' workbook exists and was created/modified during the task.
2. VLM Final State: Verify line chart, monthly X-axis, and forecast visualization (dashed line/shaded area).
3. VLM Trajectory: Verify workflow (Analytics pane usage).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_line_forecast(traj, env_info, task_info):
    """
    Verify the creation of a line chart with a 3-period forecast.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Programmatic Results (File Check)
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        result_data = {"workbook_exists": False}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Scoring: File Existence (20 pts)
    if result_data.get("workbook_exists", False):
        score += 20
        feedback_parts.append("Workbook 'Supply_Chain_Forecast' saved successfully.")
    else:
        feedback_parts.append("Workbook 'Supply_Chain_Forecast' not found or not saved.")

    # 2. VLM Final Screenshot Verification (50 pts)
    final_screenshot = get_final_screenshot(traj)
    vlm_final_score = 0
    
    if final_screenshot:
        final_prompt = """
        Analyze this screenshot of Oracle Analytics Desktop.
        I am looking for a Line Chart showing Revenue over Time (Months) with a Forecast.
        
        Please verify:
        1. Is there a Line Chart visible? (yes/no)
        2. Is the X-axis showing monthly time labels (e.g., Jan, Feb, 2020-01)? (yes/no)
        3. Is there a visible forecast extension? (Look for a lighter/dashed line extending to the right of the main line, or a shaded confidence band at the end). (yes/no)
        4. Does the forecast look like it projects about 3 data points/periods into the future? (yes/no/unclear)
        
        Respond in JSON:
        {
            "line_chart_present": boolean,
            "monthly_axis": boolean,
            "forecast_visible": boolean,
            "forecast_periods_correct": boolean
        }
        """
        
        vlm_res = query_vlm(image=final_screenshot, prompt=final_prompt)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("line_chart_present"):
                vlm_final_score += 15
                feedback_parts.append("Line chart visualization detected.")
            else:
                feedback_parts.append("No line chart detected.")
                
            if parsed.get("monthly_axis"):
                vlm_final_score += 10
                feedback_parts.append("Monthly X-axis detected.")
            
            if parsed.get("forecast_visible"):
                vlm_final_score += 15
                feedback_parts.append("Forecast visualization detected.")
                if parsed.get("forecast_periods_correct"):
                    vlm_final_score += 10
                    feedback_parts.append("Forecast length looks correct (approx 3 periods).")
            else:
                feedback_parts.append("No forecast extension visible.")
        else:
            feedback_parts.append("Failed to analyze final screenshot.")
    
    score += vlm_final_score

    # 3. VLM Trajectory Verification (30 pts)
    # Check if they accessed the Analytics pane
    frames = sample_trajectory_frames(traj, n=4)
    vlm_traj_score = 0
    
    if frames:
        traj_prompt = """
        Review these screenshots of a user working in Oracle Analytics Desktop.
        Did the user:
        1. Open the 'Analytics' pane (usually an icon looking like a chart with a magnifying glass or trend line)?
        2. Configure 'Forecast' settings?
        
        Respond in JSON:
        {
            "analytics_pane_opened": boolean,
            "forecast_configured": boolean
        }
        """
        
        vlm_traj_res = query_vlm(images=frames, prompt=traj_prompt)
        
        if vlm_traj_res.get("success"):
            parsed = vlm_traj_res.get("parsed", {})
            if parsed.get("analytics_pane_opened") or parsed.get("forecast_configured"):
                vlm_traj_score += 30
                feedback_parts.append("Workflow verification: Analytics/Forecast configuration observed.")
            else:
                feedback_parts.append("Workflow verification: Analytics pane usage not clearly observed.")
        else:
             # Fallback if VLM fails but final state is good
             if vlm_final_score >= 40:
                 vlm_traj_score = 30
                 feedback_parts.append("Workflow inferred from valid final state.")
    
    score += vlm_traj_score

    # Pass Threshold
    # Must have saved file AND have visible forecast (file=20, forecast=15 minimum) -> 35
    # Let's set bar at 60
    passed = score >= 60 and result_data.get("workbook_exists", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }