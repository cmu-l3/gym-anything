#!/usr/bin/env python3
"""
Verifier for check_hepc_regimen_sorafenib task.

Verifies:
1. Report file creation and content (Programmatic)
2. Correct navigation and drug lookup (VLM Trajectory)
3. Correct interaction color reporting (Hybrid)
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_check_hepc_regimen(traj, env_info, task_info):
    """
    Verify the Hepatitis C regimen check task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    sofosbuvir_colors = metadata.get('sofosbuvir_colors', ['green', 'grey', 'yellow'])
    velpatasvir_colors = metadata.get('velpatasvir_colors', ['orange', 'amber', 'yellow', 'red'])

    # ================================================================
    # 1. Load Programmatic Results
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 2. Analyze File Content (50 Points)
    # ================================================================
    file_exists = result.get("output_file_exists", False)
    content = result.get("file_content", "")
    
    if file_exists:
        score += 10
        feedback_parts.append("Report file created")
        
        # Normalize content for checking
        content_lower = content.lower()
        
        # Check Sorafenib mention
        if "sorafenib" in content_lower:
            score += 5
            feedback_parts.append("Sorafenib identified")
        else:
            feedback_parts.append("Missing 'Sorafenib' in report")
            
        # Check Sofosbuvir
        if "sofosbuvir" in content_lower:
            score += 5
            # Extract color
            found_sof_color = False
            for color in sofosbuvir_colors:
                if color in content_lower and "sofosbuvir" in content_lower.split(color)[0].split('\n')[-1]:
                    score += 10
                    feedback_parts.append(f"Sofosbuvir color correct ({color})")
                    found_sof_color = True
                    break
            if not found_sof_color:
                feedback_parts.append("Sofosbuvir color incorrect or missing")
        else:
            feedback_parts.append("Missing 'Sofosbuvir' in report")

        # Check Velpatasvir
        if "velpatasvir" in content_lower:
            score += 5
            # Extract color
            found_vel_color = False
            for color in velpatasvir_colors:
                if color in content_lower and "velpatasvir" in content_lower.split(color)[0].split('\n')[-1]:
                    score += 10
                    feedback_parts.append(f"Velpatasvir color correct ({color})")
                    found_vel_color = True
                    break
            if not found_vel_color:
                feedback_parts.append("Velpatasvir color incorrect or missing")
        else:
            feedback_parts.append("Missing 'Velpatasvir' in report")
            
    else:
        feedback_parts.append("Report file NOT created")

    # ================================================================
    # 3. VLM Trajectory Verification (50 Points)
    # ================================================================
    # We need to verify the agent actually looked these up in the app
    # rather than guessing.
    
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    You are verifying an agent's interaction with the 'Liverpool Cancer iChart' app.
    The agent was supposed to:
    1. Search for 'Sorafenib'
    2. Go to 'Antivirals'
    3. Look up 'Sofosbuvir' and 'Velpatasvir'

    Examine the screenshots sequence.
    
    Return JSON:
    {
        "saw_sorafenib": true/false,
        "saw_antivirals_list": true/false,
        "saw_sofosbuvir_or_velpatasvir": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get("parsed", {})
    
    if vlm_data.get("saw_sorafenib"):
        score += 15
        feedback_parts.append("VLM: Saw Sorafenib navigation")
    
    if vlm_data.get("saw_antivirals_list"):
        score += 15
        feedback_parts.append("VLM: Saw Antivirals category")
        
    if vlm_data.get("saw_sofosbuvir_or_velpatasvir"):
        score += 20
        feedback_parts.append("VLM: Saw specific drugs in list")
    
    # ================================================================
    # Final Scoring
    # ================================================================
    passed = score >= 60 and file_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }