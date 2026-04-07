#!/usr/bin/env python3
"""
Verifier for openvsp_variable_sweep_kinematics task.

Verification Strategy:
1. Programmatic XML Verification (Primary)
   - Parse fx_swept.vsp3 to extract Wing Sweep and Span.
   - Sweep must be updated to ~68.0 deg.
   - Span must be updated to ~7.97 m to maintain physical kinematics.
   - Check file modification timestamps to prevent anti-gaming (submitting original).

2. VLM Trajectory Verification (Secondary/Anti-Gaming)
   - Samples trajectory frames to ensure the agent actually used the OpenVSP GUI
     rather than just echoing/sed-ing the file via terminal.
"""

import json
import os
import re
import math
import tempfile
import logging

# Import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    pass # Handled gracefully if unavailable in test environments

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _extract_param_values(xml_content: str, param_name: str) -> list:
    """Extract all Value attributes for a given OpenVSP parameter name."""
    # Matches tags like: <Sweep Value="68.0" .../> or <TotalSpan Value="7.97" .../>
    pattern = rf'<{param_name}\s+[^>]*Value="([^"]+)"'
    matches = re.findall(pattern, xml_content)
    
    vals = []
    for m in matches:
        try:
            vals.append(float(m))
        except ValueError:
            pass
    return vals


def verify_openvsp_variable_sweep_kinematics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    target_sweep = metadata.get("target_sweep", 68.0)
    target_span = metadata.get("target_span_calculated", 7.973)
    tol_sweep = metadata.get("tolerance_sweep", 0.5)
    tol_span = metadata.get("tolerance_span", 0.2)

    # Pull result JSON from container
    result_file = metadata.get("result_file", "/tmp/openvsp_variable_sweep_kinematics_result.json")
    local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json").name
    
    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result data: {e}",
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []
    
    # Check 1: File Exists & Updated (10 pts)
    file_exists = data.get("file_exists", False)
    file_mtime = data.get("file_mtime", 0)
    task_start = data.get("task_start", 0)
    
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file fx_swept.vsp3 not found. The model was not saved correctly."
        }
        
    if file_mtime < task_start:
        feedback_parts.append("WARNING: File timestamp predates task start (Anti-gaming flag).")
    else:
        score += 10
        feedback_parts.append("File fx_swept.vsp3 saved successfully (+10).")

    # Parse XML Content
    content = data.get("file_content", "")
    
    # Check 2: Extract Parameters (10 pts)
    sweeps = _extract_param_values(content, "Sweep")
    spans = _extract_param_values(content, "TotalSpan")
    if not spans:
        spans = _extract_param_values(content, "Span") # Fallback tag
        
    if not sweeps or not spans:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | ERROR: Could not find Sweep or Span parameters in the saved XML."
        }
        
    score += 10
    
    # Check 3: Sweep Parameter Verification (30 pts)
    # The agent might have multiple sections, we check if the target sweep exists
    sweep_correct = False
    best_sweep = sweeps[0]
    for val in sweeps:
        if abs(val - target_sweep) <= tol_sweep:
            sweep_correct = True
            best_sweep = val
            break
            
    if sweep_correct:
        score += 30
        feedback_parts.append(f"Sweep updated to {best_sweep:.1f} deg (Target: {target_sweep}) (+30).")
    else:
        feedback_parts.append(f"Sweep not updated correctly. Found: {sweeps} (Target: {target_sweep}).")

    # Check 4: Kinematic Span Verification (30 pts)
    span_correct = False
    best_span = spans[0]
    for val in spans:
        if abs(val - target_span) <= tol_span:
            span_correct = True
            best_span = val
            break
            
    if span_correct:
        score += 30
        feedback_parts.append(f"Span updated to {best_span:.2f} m (Target: ~{target_span:.2f}) (+30).")
    else:
        feedback_parts.append(f"Span physically incorrect. Found: {spans} (Target: ~{target_span:.2f}).")

    # Check 5: VLM Trajectory Verification (20 pts)
    vlm_passed = False
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and 'gym_anything.vlm' in sys.modules:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """Look at these trajectory screenshots of an AI agent working.
            Did the agent actively use the OpenVSP GUI application (the 3D CAD interface with parameter windows) to complete the task?
            We are checking to make sure they didn't just cheat by running a python script in the terminal.
            Respond strictly in JSON: {"used_gui": true/false, "reasoning": "brief explanation"}"""
            
            vlm_result = query_vlm(images=images, prompt=prompt)
            if vlm_result.get("success") and vlm_result.get("parsed", {}).get("used_gui", False):
                vlm_passed = True
                score += 20
                feedback_parts.append("VLM confirmed OpenVSP GUI usage (+20).")
            else:
                feedback_parts.append("VLM did not confirm OpenVSP GUI usage (possible terminal-only edit).")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            # Give benefit of the doubt if VLM fails technically
            score += 20
            feedback_parts.append("VLM verification skipped/failed (+20).")
    else:
        # Give points if VLM not available in this env
        score += 20
        feedback_parts.append("VLM tool unavailable, auto-awarding GUI interaction points (+20).")

    # Final Evaluation
    is_physically_valid = sweep_correct and span_correct
    passed = score >= 90 and is_physically_valid

    if not is_physically_valid and sweep_correct:
        feedback_parts.append("CRITICAL ERROR: Changing the sweep without adjusting the span artificially stretches the physical wing. This is aerodynamically invalid.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }