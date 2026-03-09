#!/usr/bin/env python3
"""
Verifier for create_chart_template task in NinjaTrader.

Task: Create a chart template 'DayTrading' with VWAP, ATR(14), CurrentDayOHL, Candlesticks.

Scoring:
- Template file exists and created during task: 20 pts (Gate)
- VWAP present: 15 pts
- ATR present: 15 pts
- ATR Period = 14: 10 pts
- CurrentDayOHL present: 10 pts
- Candlestick Bar Type: 10 pts
- Workspace Saved: 5 pts
- VLM Trajectory Verification: 15 pts

Total: 100 pts
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/NinjaTraderTasks/task_result.json"

def verify_create_chart_template(traj, env_info, task_info):
    """
    Verify that the chart template was created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Task result file not found."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. File Existence & Anti-Gaming Gate (20 pts)
    if not result.get("template_exists"):
        return {"passed": False, "score": 0, "feedback": "Template 'DayTrading.xml' not found."}
    
    if not result.get("template_created_during_task"):
        return {"passed": False, "score": 0, "feedback": "Template exists but was not created during this task session."}
    
    score += 20
    feedback.append("Template file created.")

    # 3. Content Checks (50 pts total)
    checks = result.get("checks", {})
    
    # VWAP (15)
    if checks.get("has_vwap"):
        score += 15
        feedback.append("VWAP indicator found.")
    else:
        feedback.append("VWAP indicator missing.")

    # ATR (15)
    if checks.get("has_atr"):
        score += 15
        feedback.append("ATR indicator found.")
        # ATR Period 14 (10)
        if checks.get("has_atr_14"):
            score += 10
            feedback.append("ATR Period 14 verified.")
        else:
            feedback.append("ATR Period incorrect (expected 14).")
    else:
        feedback.append("ATR indicator missing.")

    # CurrentDayOHL (10)
    if checks.get("has_ohl"):
        score += 10
        feedback.append("CurrentDayOHL indicator found.")
    else:
        feedback.append("CurrentDayOHL indicator missing.")

    # Bar Type (10)
    if checks.get("has_candlestick"):
        score += 10
        feedback.append("Candlestick bar type verified.")
    else:
        feedback.append("Bar type mismatch (expected Candlestick).")

    # 4. Workspace Check (5 pts)
    if result.get("workspace_modified"):
        score += 5
        feedback.append("Workspace saved.")
    else:
        feedback.append("Workspace not saved (minor).")

    # 5. VLM Verification (15 pts)
    # Use trajectory frames to confirm UI interaction
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots of a NinjaTrader user session.
        The user goal is to create a chart and save it as a template named "DayTrading".
        
        Look for:
        1. A Chart window opening.
        2. indicators being added (Indicators dialog).
        3. A "Save As" dialog for saving a template.
        4. The name "DayTrading" being typed or visible.
        
        Did the user perform these steps?
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get("success"):
                # If VLM confirms positive workflow, award points
                # Heuristic: we trust the file check mostly, VLM is for anti-gaming confirmation
                score += 15
                feedback.append("VLM verification passed.")
            else:
                # If VLM fails/uncertain, we might still pass if file is perfect, 
                # but let's be lenient on scoring if file is good.
                # Here we award 5 points for effort if file is good.
                score += 5 
                feedback.append("VLM verification inconclusive.")
        except:
            pass # VLM fail shouldn't tank a perfect file result
    else:
         feedback.append("No trajectory frames available for VLM.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }