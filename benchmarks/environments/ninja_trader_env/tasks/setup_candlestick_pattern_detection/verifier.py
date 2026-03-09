#!/usr/bin/env python3
"""
Verifier for setup_candlestick_pattern_detection task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_candlestick_patterns(traj, env_info, task_info):
    """
    Verify that the agent set up Doji (Blue) and Hammer (Magenta) indicators on a SPY chart.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define score components
    SCORING = {
        "workspace_saved": 20,
        "spy_chart_created": 20,
        "doji_indicator": 20,
        "hammer_indicator": 20,
        "colors_correct": 20
    }
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Retrieve Result JSON
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            # NinjaTrader is Windows, but path handling in copy_from_env should ideally handle abstraction
            # If running in a Windows container, paths might need care.
            # Assuming the standard path mapped in export_result.ps1
            copy_from_env("C:\\Users\\Docker\\Desktop\\NinjaTraderTasks\\task_result.json", temp_file.name)
            
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve task result file: {str(e)}. Did the agent save the workspace?"
            }
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)

        # 2. Evaluate Scoring Criteria
        
        # Criterion 1: Workspace Saved
        if result.get("workspace_saved", False):
            score += SCORING["workspace_saved"]
            feedback_parts.append("Workspace saved successfully.")
        else:
            feedback_parts.append("Workspace NOT saved or modified.")

        # Criterion 2: SPY Chart Created
        if result.get("spy_chart_found", False):
            score += SCORING["spy_chart_created"]
            feedback_parts.append("SPY chart found.")
        else:
            feedback_parts.append("SPY chart NOT found.")

        # Criterion 3: Doji Indicator
        if result.get("doji_configured", False):
            score += SCORING["doji_indicator"]
            feedback_parts.append("Doji indicator present.")
        else:
            feedback_parts.append("Doji indicator missing.")

        # Criterion 4: Hammer Indicator
        if result.get("hammer_configured", False):
            score += SCORING["hammer_indicator"]
            feedback_parts.append("Hammer indicator present.")
        else:
            feedback_parts.append("Hammer indicator missing.")

        # Criterion 5: Colors Correct
        colors_score = 0
        if result.get("doji_color_correct", False):
            colors_score += 10
            feedback_parts.append("Doji color correct (Blue).")
        else:
            feedback_parts.append("Doji color INCORRECT.")

        if result.get("hammer_color_correct", False):
            colors_score += 10
            feedback_parts.append("Hammer color correct (Magenta).")
        else:
            feedback_parts.append("Hammer color INCORRECT.")
        
        score += colors_score

        # 3. Determine Pass/Fail
        # Pass threshold is 80 (Must have saved, chart, both indicators correct)
        # Allows failing one color check, or minor workspace issue if indicators are perfect (unlikely if not saved)
        passed = score >= 80

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with error: {str(e)}"}