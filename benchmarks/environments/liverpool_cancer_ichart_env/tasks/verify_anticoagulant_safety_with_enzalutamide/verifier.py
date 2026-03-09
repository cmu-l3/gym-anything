#!/usr/bin/env python3
"""
Verifier for verify_anticoagulant_safety_with_enzalutamide task.

Verification Strategy:
1. VLM Trajectory Analysis (50pts): Did the agent select Enzalutamide -> Warfarin -> View Result?
2. VLM Final State Analysis (35pts): Is the correct interaction detail page shown with Red/Orange warning?
3. Anti-Gaming (15pts): App visible, keywords present in XML, timestamps valid.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, List

# Simulated import for the framework's VLM utilities
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for testing outside framework
    def query_vlm(prompt, image=None, images=None):
        return {"success": False, "error": "VLM module not found"}
    def sample_trajectory_frames(traj, n=5):
        return []
    def get_final_screenshot(traj):
        return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_anticoagulant_safety(traj, env_info, task_info):
    """
    Verifies the Enzalutamide + Warfarin interaction check.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Anti-Gaming & Basics (15 Points)
    # ---------------------------------------------------------
    app_visible = result_data.get("app_visible", False)
    xml_keywords = result_data.get("xml_keywords_present", False)
    
    if app_visible:
        score += 5
    else:
        feedback_parts.append("App was not in foreground at end.")

    # XML Keywords (Enzalutamide + Warfarin present in UI dump)
    if xml_keywords:
        score += 5
        feedback_parts.append("Drugs found in UI hierarchy.")
    else:
        feedback_parts.append("Drugs not detected in UI layout (might be image-based text).")

    # Workflow consistency (Time check)
    task_start = result_data.get("task_start", 0)
    task_end = result_data.get("task_end", 0)
    if task_end > task_start and (task_end - task_start) > 5:
        score += 5
    else:
        feedback_parts.append("Task duration suspicious.")

    # ---------------------------------------------------------
    # VLM Trajectory Analysis (50 Points)
    # ---------------------------------------------------------
    frames = sample_trajectory_frames(traj, n=6)
    
    traj_prompt = """
    Analyze these chronological screenshots of a medical app interaction.
    The user should be:
    1. Selecting a Cancer Drug "Enzalutamide" (or scrolling to 'E').
    2. Selecting a Co-medication "Warfarin" (or scrolling to 'W').
    3. Viewing an Interaction Result (likely Red or Orange traffic light).
    4. Viewing Details.

    Return JSON:
    {
        "seen_enzalutamide_selection": boolean,
        "seen_warfarin_selection": boolean,
        "seen_interaction_result": boolean,
        "seen_details_page": boolean,
        "traffic_light_color": "red" | "orange" | "yellow" | "green" | "unknown"
    }
    """
    
    traj_analysis = query_vlm(images=frames, prompt=traj_prompt)
    
    if traj_analysis.get("success"):
        parsed = traj_analysis.get("parsed", {})
        
        if parsed.get("seen_enzalutamide_selection"):
            score += 10
            feedback_parts.append("Trajectory: Enzalutamide selection observed.")
        
        if parsed.get("seen_warfarin_selection"):
            score += 10
            feedback_parts.append("Trajectory: Warfarin selection observed.")
            
        if parsed.get("seen_interaction_result"):
            score += 15
            feedback_parts.append("Trajectory: Interaction result observed.")
            
        if parsed.get("seen_details_page"):
            score += 15
            feedback_parts.append("Trajectory: Details page opened.")
            
        traj_color = parsed.get("traffic_light_color", "unknown")
    else:
        feedback_parts.append("Trajectory analysis failed.")
        traj_color = "unknown"

    # ---------------------------------------------------------
    # VLM Final State Analysis (35 Points)
    # ---------------------------------------------------------
    final_img = get_final_screenshot(traj)
    
    final_prompt = """
    Analyze this final screenshot of the Liverpool Cancer iChart app.
    
    Verify:
    1. Are "Enzalutamide" and "Warfarin" visible as the selected pair?
    2. Is the interaction severity color visible (Red or Orange)?
    3. Is there clinical text describing the interaction (e.g. CYP induction, INR monitoring)?
    
    Return JSON:
    {
        "correct_drug_pair": boolean,
        "severity_color": "red" | "orange" | "yellow" | "green" | "grey" | "none",
        "clinical_text_visible": boolean
    }
    """
    
    final_analysis = query_vlm(image=final_img, prompt=final_prompt)
    
    if final_analysis.get("success"):
        parsed = final_analysis.get("parsed", {})
        
        # Correct Pair
        if parsed.get("correct_drug_pair"):
            score += 10
            feedback_parts.append("Final: Correct drug pair displayed.")
        else:
            feedback_parts.append("Final: Drug pair not clearly visible.")

        # Severity Color (Red or Orange is acceptable for this high-risk interaction)
        color = parsed.get("severity_color", "").lower()
        if "red" in color or "orange" in color:
            score += 10
            feedback_parts.append(f"Final: Correct severity color ({color}).")
        else:
            feedback_parts.append(f"Final: Incorrect or missing severity color ({color}).")

        # Clinical Text
        if parsed.get("clinical_text_visible"):
            score += 15
            feedback_parts.append("Final: Clinical details visible.")
        else:
            feedback_parts.append("Final: Clinical details missing.")
    else:
        feedback_parts.append("Final screenshot analysis failed.")

    # ---------------------------------------------------------
    # Final Result Calculation
    # ---------------------------------------------------------
    
    # Pass threshold: 60 points
    # Must have at least verified the drugs (Trajectory selection OR Final pair visible)
    # AND seen the result.
    
    key_criteria_met = (
        (traj_analysis.get("success") and traj_analysis.get("parsed", {}).get("seen_interaction_result")) or 
        (final_analysis.get("success") and final_analysis.get("parsed", {}).get("severity_color") in ["red", "orange"])
    )
    
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }