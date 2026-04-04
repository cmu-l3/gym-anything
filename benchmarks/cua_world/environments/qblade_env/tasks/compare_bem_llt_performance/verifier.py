#!/usr/bin/env python3
"""
Verifier for compare_bem_llt_performance task.

Checks:
1. Valid QBlade project file saved.
2. Project file contains internal evidence of LLT simulation (anti-gaming).
3. Text report exists with reasonable Cp values.
4. Visual verification of wake simulation (via VLM).
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any

# Import VLM utils if available in the environment
try:
    from vlm_utils import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for standalone testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compare_bem_llt_performance(traj, env_info, task_info):
    """
    Verifies the comparative aerodynamic analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_cp = metadata.get('min_cp', 0.3)
    max_cp = metadata.get('max_cp', 0.55)

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Project Saved (10 pts) ---
    if result.get('project_exists') == "true":
        score += 10
        feedback_parts.append("Project file saved")
    elif result.get('project_exists') == "false_stale":
        feedback_parts.append("Project file exists but was not modified (stale)")
    else:
        feedback_parts.append("Project file not found")

    # --- Criterion 2: BEM Simulation Evidence (20 pts) ---
    if result.get('has_bem_data'):
        score += 20
        feedback_parts.append("BEM simulation data found in project")
    else:
        feedback_parts.append("No BEM simulation data detected")

    # --- Criterion 3: LLT Simulation Evidence (30 pts) ---
    # This is the heavy lifter for anti-gaming. LLT is complex to run.
    if result.get('has_llt_data'):
        score += 30
        feedback_parts.append("LLT simulation data found in project")
    else:
        feedback_parts.append("No LLT simulation data detected (Critical)")

    # --- Criterion 4: Report and Values (20 pts total) ---
    report_content = result.get('report_content', "")
    values_found = []
    
    if result.get('report_exists'):
        score += 10
        feedback_parts.append("Report file created")
        
        # Extract floating point numbers
        floats = [float(x) for x in re.findall(r"0\.\d+", report_content)]
        values_found = floats
        
        valid_values = [v for v in floats if min_cp <= v <= max_cp]
        if len(valid_values) >= 2:
            score += 10
            feedback_parts.append(f"Reasonable Cp values reported: {valid_values}")
        elif len(valid_values) == 1:
            score += 5
            feedback_parts.append(f"One reasonable Cp value found: {valid_values}")
        else:
            feedback_parts.append(f"Values in report ({floats}) outside expected range [{min_cp}, {max_cp}]")
    else:
        feedback_parts.append("Report file missing")

    # --- Criterion 5: Visual Verification (20 pts) ---
    # We check if the agent saved a screenshot OR if the VLM sees the wake in trajectory
    
    visual_score = 0
    
    # A. Agent saved screenshot check
    if result.get('agent_screenshot_found'):
        visual_score += 10
        feedback_parts.append("Agent saved a screenshot")

    # B. VLM check on trajectory
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "You are verifying a wind turbine simulation task. "
            "Look at these screenshots of the QBlade software. "
            "Do you see a 3D visualization of a wind turbine wake? "
            "Specifically, look for helical vortices or streamtubes trailing behind the rotor blades. "
            "This usually appears as colored lines or spirals in a 3D viewport. "
            "Return JSON: {\"wake_visible\": true/false, \"confidence\": \"low/medium/high\"}"
        )
        
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('wake_visible'):
                visual_score = 20 # Full points if VLM confirms, overrides file check
                feedback_parts.append("VLM confirmed 3D wake visualization")
            else:
                feedback_parts.append("VLM did not see wake visualization")
        else:
            feedback_parts.append("VLM check failed")
    
    # Cap visual score at 20
    score += min(visual_score, 20)

    # --- Final Result ---
    # Must have LLT evidence to pass
    passed = (score >= 70) and result.get('has_llt_data')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }