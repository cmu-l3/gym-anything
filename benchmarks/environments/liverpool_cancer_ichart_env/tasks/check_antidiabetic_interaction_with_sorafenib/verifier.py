#!/usr/bin/env python3
"""
Verifier for check_antidiabetic_interaction_with_sorafenib task.
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
    # Fallback/Mock for testing without framework
    def query_vlm(**kwargs): return {"success": False, "error": "ImportError"}
    def sample_trajectory_frames(traj, n): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_interaction_check(traj, env_info, task_info):
    """
    Verify the agent checked the Sorafenib-Metformin interaction.
    
    Scoring Criteria:
    1. Output file exists and was created during task (20 pts)
    2. Output file contains a valid color (Red/Orange/Yellow/Green/Grey) (20 pts)
    3. Output file contains clinical text (10 pts)
    4. VLM: Agent navigated to Sorafenib (15 pts)
    5. VLM: Agent located Metformin (15 pts)
    6. VLM: Interaction detail/result was visible (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result Data
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 2. Evaluate File Existence & Anti-Gaming
    file_exists = result_data.get("file_exists", False)
    fresh_file = result_data.get("file_created_during_task", "false")
    
    if file_exists:
        if fresh_file == "true" or fresh_file == "unknown":
            score += 20
            feedback_parts.append("Result file created successfully.")
        else:
            feedback_parts.append("Result file exists but timestamp indicates it is old.")
    else:
        feedback_parts.append("Result file /sdcard/interaction_result.txt not found.")

    # 3. Evaluate Content (Color and Text)
    content = result_data.get("file_content", "").strip()
    valid_colors = ["red", "orange", "yellow", "green", "grey"]
    reported_color = None
    
    lines = content.split('\\n') if '\\n' in content else content.split('\n')
    
    if file_exists and lines:
        # Check first line for color
        first_line_lower = lines[0].lower().strip()
        for color in valid_colors:
            if color in first_line_lower:
                reported_color = color
                score += 20
                feedback_parts.append(f"Valid color reported: {color}.")
                break
        
        if not reported_color:
            feedback_parts.append("First line did not contain a valid interaction color.")

        # Check for clinical text (length > 15 chars)
        full_text = " ".join(lines[1:])
        if len(full_text) > 15:
            score += 10
            feedback_parts.append("Clinical summary text present.")
        else:
            feedback_parts.append("Clinical summary text missing or too short.")

    # 4. VLM Verification (Trajectory Analysis)
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        frames.append(final_screen)

    vlm_prompt = """
    Analyze these screenshots of the 'Liverpool Cancer iChart' app.
    The user task is to check the interaction between 'Sorafenib' and 'Metformin'.
    
    Look for:
    1. The cancer drug name 'Sorafenib' selected or visible.
    2. The co-medication 'Metformin' selected or visible.
    3. An interaction result page (traffic light color banner).
    4. A detail view showing clinical text/recommendations.
    
    Respond in JSON:
    {
        "sorafenib_seen": boolean,
        "metformin_seen": boolean,
        "result_page_seen": boolean,
        "observed_color": "red/orange/yellow/green/grey/none",
        "detail_text_visible": boolean
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("sorafenib_seen"):
            score += 15
            feedback_parts.append("VLM confirmed Sorafenib selection.")
        else:
            feedback_parts.append("VLM did not see Sorafenib selected.")
            
        if parsed.get("metformin_seen"):
            score += 15
            feedback_parts.append("VLM confirmed Metformin selection.")
        else:
            feedback_parts.append("VLM did not see Metformin selected.")
            
        if parsed.get("result_page_seen") or parsed.get("detail_text_visible"):
            score += 20
            feedback_parts.append("VLM confirmed result/detail page view.")
        else:
            feedback_parts.append("VLM did not see the interaction result page.")
            
        # Optional: Cross-verify reported color with VLM observed color
        observed_color = parsed.get("observed_color", "none")
        if reported_color and observed_color != "none":
            if reported_color in observed_color or observed_color in reported_color:
                feedback_parts.append("Reported color matches VLM observation.")
            else:
                feedback_parts.append(f"Warning: Reported {reported_color} but VLM saw {observed_color}.")
                
    else:
        feedback_parts.append("VLM verification failed to run.")

    # Final Pass Decision
    # Need at least file existence + color + some VLM confirmation
    passed = (score >= 60) and file_exists and (reported_color is not None)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }