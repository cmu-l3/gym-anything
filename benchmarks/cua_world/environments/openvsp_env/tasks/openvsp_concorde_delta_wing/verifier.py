#!/usr/bin/env python3
"""
Verifier for openvsp_concorde_delta_wing task.

Checks that the agent created a highly swept delta wing and modified the XSec profile
to a supersonic (Biconvex) shape with the correct 3% thickness.

Scoring (100 points total):
  1. File Creation & Anti-Gaming: File exists and created during task (10 pts)
  2. Component Naming: Wing exists and named 'Concorde_Wing' (10 pts)
  3. Planform Dimensions: Span, Chords, Sweep match ±5% (25 pts)
  4. Airfoil Type: Type modified to Biconvex (10) from default NACA (7) (35 pts)
  5. Airfoil Thickness: ThickChord modified to 0.03 (20 pts)
  
Pass threshold: 70 points (requires successfully changing the Airfoil Type).
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Spec Targets
TARGET_SPAN = 25.6
TARGET_ROOT = 34.0
TARGET_TIP = 2.0
TARGET_SWEEP = 60.0
TARGET_TYPE = 10.0      # OpenVSP Enum for Biconvex Airfoil
TARGET_THICKNESS = 0.03 # 3% T/C

def _find_param_values(content: str, tag: str) -> list:
    """Find all Value attributes for elements with the given tag name via Regex (fallback for nested/flat XML)."""
    pattern = rf'<{tag}\s+Value="([^"]+)"'
    vals = []
    for m in re.finditer(pattern, content):
        try:
            vals.append(float(m.group(1)))
        except ValueError:
            pass
    return vals

def verify_concorde_wing(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/openvsp_concorde_result.json", local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # --- CRITERION 1: File Exists & Anti-Gaming (10 pts) ---
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "concorde_wing.vsp3 not found. Agent did not save the file."
        }
    
    if data.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task (+10)")
    else:
        # Penalize if it looks like a pre-existing file was just left there
        feedback_parts.append("Warning: File timestamp indicates it was not created during this task")

    content = data.get("file_content", "").replace("\\n", "\n")
    
    # Check XML validity
    try:
        ET.fromstring(content)
    except ET.ParseError as e:
        return {"passed": False, "score": score, "feedback": f"File is not valid XML: {e}"}

    # --- CRITERION 2: Component Name (10 pts) ---
    has_wing = "<WingGeom>" in content or "WingGeom" in content
    named_correctly = "<Name>Concorde_Wing</Name>" in content
    
    if named_correctly:
        score += 10
        feedback_parts.append("Component correctly named Concorde_Wing (+10)")
    elif has_wing:
        score += 5
        feedback_parts.append("Wing component found but not named 'Concorde_Wing' (+5)")
    else:
        feedback_parts.append("No Wing component found (+0)")

    # --- CRITERION 3: Planform Dimensions (25 pts) ---
    span_vals = _find_param_values(content, "TotalSpan")
    root_vals = _find_param_values(content, "Root_Chord")
    tip_vals = _find_param_values(content, "Tip_Chord")
    sweep_vals = _find_param_values(content, "Sweep")
    
    planform_pts = 0
    if any(abs(v - TARGET_SPAN) <= TARGET_SPAN * 0.05 for v in span_vals):
        planform_pts += 6.25
    if any(abs(v - TARGET_ROOT) <= TARGET_ROOT * 0.05 for v in root_vals):
        planform_pts += 6.25
    if any(abs(v - TARGET_TIP) <= TARGET_TIP * 0.05 for v in tip_vals):
        planform_pts += 6.25
    if any(abs(v - TARGET_SWEEP) <= TARGET_SWEEP * 0.05 for v in sweep_vals):
        planform_pts += 6.25
        
    score += planform_pts
    feedback_parts.append(f"Planform dimensions score: {planform_pts}/25")

    # --- CRITERION 4: Airfoil Type (35 pts) ---
    # Default NACA is 7. Biconvex is 10. 
    type_vals = _find_param_values(content, "Type")
    
    # We want ALL relevant Type values to be 10. OpenVSP usually has a few for the Wing.
    # At least one Biconvex type must be present, and ideally no 7s.
    if 10.0 in type_vals or 11.0 in type_vals:  # 11 is wedge, give credit if they chose another supersonic shape
        score += 35
        feedback_parts.append("Airfoil Type successfully changed to Biconvex (10) (+35)")
    elif 7.0 in type_vals:
        feedback_parts.append("Airfoil Type remained default subsonic NACA (7) (+0)")
    else:
        feedback_parts.append(f"Airfoil Type not found or unrecognized: {type_vals[:3]} (+0)")

    # --- CRITERION 5: Airfoil Thickness (20 pts) ---
    thick_vals = _find_param_values(content, "ThickChord")
    
    # Default is 0.10. We want 0.03.
    correct_thickness = [v for v in thick_vals if 0.025 <= v <= 0.035]
    if correct_thickness:
        score += 20
        feedback_parts.append(f"Thickness (T/C) successfully set to ~0.03 (+20)")
    else:
        if thick_vals:
            feedback_parts.append(f"Thickness incorrect (found {thick_vals[:2]}, expected 0.03) (+0)")
        else:
            feedback_parts.append("Thickness parameter not found (+0)")

    # --- Optional VLM Check for robustness ---
    vlm_bonus = 0
    if "query_vlm" in env_info and score >= 40:
        from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames
        
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots from an OpenVSP session.
        Did the agent successfully model a delta wing (triangle shape) resembling a Concorde wing?
        Respond with {"is_delta_wing": true/false}
        """
        vlm_res = env_info["query_vlm"](images=frames + [final] if final else frames, prompt=prompt)
        if vlm_res.get("success") and vlm_res.get("parsed", {}).get("is_delta_wing"):
            logger.info("VLM confirmed delta wing geometry.")
            # VLM check is purely a bonus confirmation here since XML parsing is deterministically true.

    # Overall Pass/Fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }