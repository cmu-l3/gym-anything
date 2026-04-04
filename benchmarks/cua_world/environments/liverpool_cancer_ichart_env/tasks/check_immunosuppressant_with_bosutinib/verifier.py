#!/usr/bin/env python3
"""
Verifier for check_immunosuppressant_with_bosutinib task.

Verification Strategy:
1. Programmatic: Check if app was open and running at end of task.
2. VLM (Trajectory): Verify the agent navigated from Cancer Drugs -> Bosutinib -> Co-meds -> Ciclosporin.
3. VLM (Final State): Verify the interaction result (Traffic Light Color) is visible.

Multi-Signal Scoring:
- App Running: 10 pts
- Trajectory Verification (Workflow): 50 pts
- Final Result Verification (Correct Drugs + Result Visible): 40 pts
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

# Import VLM utilities from the framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for testing environments without the library
    def query_vlm(**kwargs): return {"success": False, "error": "VLM lib not found"}
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_check_immunosuppressant_with_bosutinib(traj, env_info, task_info):
    """
    Verify the agent checked the interaction between Bosutinib and Ciclosporin.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Retrieve Programmatic Evidence
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    app_running = result_data.get("app_running", False)
    
    score = 0
    feedback_parts = []

    if app_running:
        score += 10
        feedback_parts.append("App was active at end of task.")
    else:
        feedback_parts.append("App was NOT active at end of task.")

    # ================================================================
    # 2. VLM Trajectory Verification (50 points)
    # ================================================================
    # specific prompt to check if agent selected the correct drugs
    traj_frames = sample_trajectory_frames(traj, n=8)
    
    trajectory_prompt = """
    You are verifying an agent's workflow in the 'Liverpool Cancer iChart' app.
    The goal is to check an interaction between 'Bosutinib' (cancer drug) and 'Ciclosporin' (co-medication).
    
    Look at the sequence of screenshots. Did the agent:
    1. Select 'Bosutinib' from a list or search results?
    2. Select 'Ciclosporin' (or Cyclosporine) from a list or search results?
    3. Reach a result screen showing interaction details?
    
    Respond in JSON:
    {
        "selected_bosutinib": boolean,
        "selected_ciclosporin": boolean,
        "reached_result_screen": boolean,
        "reasoning": "string"
    }
    """
    
    vlm_traj_result = query_vlm(
        images=traj_frames,
        prompt=trajectory_prompt
    )
    
    traj_score = 0
    if vlm_traj_result.get("success"):
        parsed = vlm_traj_result.get("parsed", {})
        if parsed.get("selected_bosutinib"):
            traj_score += 15
            feedback_parts.append("Correctly selected Bosutinib.")
        if parsed.get("selected_ciclosporin"):
            traj_score += 20  # Higher weight for the specific co-med
            feedback_parts.append("Correctly selected Ciclosporin.")
        if parsed.get("reached_result_screen"):
            traj_score += 15
            feedback_parts.append("Reached interaction result screen.")
    else:
        feedback_parts.append("VLM trajectory analysis failed.")

    score += traj_score

    # ================================================================
    # 3. VLM Final State Verification (40 points)
    # ================================================================
    final_screenshot = get_final_screenshot(traj)
    
    final_state_prompt = """
    Analyze this screenshot of the Liverpool Cancer iChart app.
    
    1. Are the names 'Bosutinib' and 'Ciclosporin' (or Cyclosporine) visible on screen?
    2. Is there a traffic-light colored interaction result visible (Red, Orange, Yellow, Green)?
    3. What is the interaction color?
    
    Respond in JSON:
    {
        "drugs_visible": boolean,
        "result_color_visible": boolean,
        "detected_color": "string (red/orange/yellow/green/grey/none)",
        "reasoning": "string"
    }
    """
    
    vlm_final_result = query_vlm(
        image=final_screenshot,
        prompt=final_state_prompt
    )
    
    final_score = 0
    if vlm_final_result.get("success"):
        parsed = vlm_final_result.get("parsed", {})
        
        if parsed.get("drugs_visible"):
            final_score += 15
            feedback_parts.append("Final screen confirms correct drug pair.")
        
        if parsed.get("result_color_visible"):
            final_score += 25
            color = parsed.get("detected_color", "unknown")
            feedback_parts.append(f"Interaction result visible (Color: {color}).")
    else:
        feedback_parts.append("VLM final screen analysis failed.")

    score += final_score

    # ================================================================
    # Final Decision
    # ================================================================
    passed = score >= 60 and app_running
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }