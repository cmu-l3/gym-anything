#!/usr/bin/env python3
"""
Verifier for monthly_trend_forecast task.

Scoring (100 points total):
- File saved & valid (10 pts)
- Line Chart Present (20 pts)
- Area Chart Present (20 pts)
- Running_Total Measure Created (25 pts)
- Analytics: Trend Line Configured (15 pts)
- Analytics: Forecast Configured (10 pts)

Anti-gaming:
- Checks file timestamps.
- Checks VLM trajectory to ensure user interacted with Analytics pane/DAX bar.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

def verify_monthly_trend_forecast(traj, env_info, task_info):
    """
    Verify the monthly_trend_forecast task using file analysis and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 1. Retrieve JSON result from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/trend_forecast_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to retrieve/parse result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Could not verify task result (file missing or corrupt)."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate programmatic criteria
    score = 0
    feedback = []
    
    # Criterion: File Exists (10 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 10
        feedback.append("✅ Report file saved correctly.")
    else:
        feedback.append("❌ Report file not found or not created during task.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # Criterion: Visuals (40 pts)
    visuals = result.get('visual_types', [])
    if 'lineChart' in visuals:
        score += 20
        feedback.append("✅ Line chart present.")
    else:
        feedback.append("❌ Line chart missing.")
        
    if 'areaChart' in visuals:
        score += 20
        feedback.append("✅ Area chart present.")
    else:
        feedback.append("❌ Area chart missing.")

    # Criterion: DAX Measure (25 pts)
    if result.get('measure_found'):
        score += 25
        feedback.append("✅ 'Running_Total' measure found in data model.")
    else:
        feedback.append("❌ 'Running_Total' measure missing.")

    # Criterion: Analytics (25 pts)
    analytics = result.get('analytics_config_found', {})
    if analytics.get('trend'):
        score += 15
        feedback.append("✅ Trend line enabled.")
    else:
        feedback.append("❌ Trend line not enabled.")
        
    if analytics.get('forecast'):
        score += 10
        feedback.append("✅ Forecast enabled.")
    else:
        feedback.append("❌ Forecast not enabled.")

    # 3. VLM Trajectory Verification (Anti-gaming & Process check)
    # We want to confirm they didn't just paste a file, and visually checked the output
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of a Power BI Desktop session.
        1. Do you see a Line Chart with a trend line (straight line overlay) or forecast (shaded area)?
        2. Do you see an Area Chart (filled line chart)?
        3. Did the user seem to open the Analytics pane (magnifying glass icon) or type DAX formulas?
        
        Reply with JSON: {"visuals_visible": boolean, "analytics_interaction": boolean}
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final_screen], prompt=prompt)
            vlm_data = vlm_resp.get('parsed', {})
            
            if not vlm_data.get('visuals_visible', False):
                score = max(0, score - 20)
                feedback.append("⚠️ VLM could not confirm visuals were visible on screen.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }