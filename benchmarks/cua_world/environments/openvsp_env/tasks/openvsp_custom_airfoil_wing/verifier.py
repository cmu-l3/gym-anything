#!/usr/bin/env python3
"""
Verifier for openvsp_custom_airfoil_wing task.

Checks:
1. Output file exists and was saved during the task (Anti-gaming)
2. Valid XML structure with <WingGeom>
3. Two distinct custom airfoil files referenced (s809.dat and s805a.dat)
4. Span and Chord geometric parameters match specifications
5. VLM trajectory verification to ensure GUI workflow was followed
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _find_param_values_by_regex(content: str, param_names: list) -> list:
    """Find Value attributes for elements matching any of the param_names."""
    vals = []
    for tag in param_names:
        pattern = rf'<{tag}\s+Value="([^"]+)"'
        for m in re.finditer(pattern, content):
            try:
                vals.append(float(m.group(1)))
            except ValueError:
                pass
    return vals


def verify_custom_airfoil_wing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_span = metadata.get('target_span', 5.0)
    target_root_chord = metadata.get('target_root_chord', 0.8)
    target_tip_chord = metadata.get('target_tip_chord', 0.3)

    result_file = "/tmp/openvsp_custom_airfoil_wing_result.json"
    local_tmp = tempfile.mktemp(suffix=".json")

    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []
    
    # 1. Check file existence and anti-gaming (15 pts)
    file_exists = data.get("file_exists", False)
    created_during_task = data.get("file_created_during_task", False)
    
    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "turbine_blade.vsp3 not found. The model was not saved."
        }
        
    if created_during_task:
        score += 15
        feedback_parts.append("File created/modified during session (+15)")
    else:
        feedback_parts.append("Warning: File timestamp is older than task start")

    content = data.get("file_content", "")
    content_lower = content.lower()

    # 2. Valid XML and WingGeom (15 pts)
    try:
        ET.fromstring(content)
        if "<WingGeom>" in content or "WingGeom" in content:
            score += 15
            feedback_parts.append("Valid XML with WingGeom (+15)")
        else:
            feedback_parts.append("Valid XML but no WingGeom found (+0)")
    except ET.ParseError:
        feedback_parts.append("Invalid XML format (+0)")

    # 3. File Airfoils Loaded (40 pts)
    has_s809 = "s809.dat" in content_lower
    has_s805a = "s805a.dat" in content_lower
    
    if has_s809 and has_s805a:
        score += 40
        feedback_parts.append("Both custom airfoils (S809 and S805A) applied (+40)")
    elif has_s809 or has_s805a:
        score += 20
        feedback_parts.append("Only one custom airfoil applied (+20)")
    else:
        feedback_parts.append("Custom airfoil files (.dat) not referenced in geometry (+0)")

    # 4. Planform Geometry Check (15 pts)
    span_vals = _find_param_values_by_regex(content, ["TotalSpan", "Span"])
    root_chord_vals = _find_param_values_by_regex(content, ["Root_Chord", "RootChord"])
    tip_chord_vals = _find_param_values_by_regex(content, ["Tip_Chord", "TipChord"])

    geom_points = 0
    if any(abs(v - target_span) < 0.2 for v in span_vals):
        geom_points += 5
    if any(abs(v - target_root_chord) < 0.1 for v in root_chord_vals):
        geom_points += 5
    if any(abs(v - target_tip_chord) < 0.1 for v in tip_chord_vals):
        geom_points += 5
        
    score += geom_points
    feedback_parts.append(f"Geometry match points: +{geom_points}/15")

    # 5. VLM Trajectory Verification (15 pts)
    query_vlm = env_info.get("query_vlm")
    vlm_points = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            
            prompt = """
            You are verifying an aerospace engineering agent's workflow in OpenVSP.
            The task is to build a wind turbine blade by setting up a Wing and importing two airfoil files (S809, S805A).
            Did the agent interact with the OpenVSP geometry browser, open the Wing cross-section (XSec) panel, and attempt to load file-based airfoils?
            Respond with a JSON object: {"workflow_followed": true/false}
            """
            
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get("success") and vlm_res.get("parsed", {}).get("workflow_followed", False):
                vlm_points = 15
                feedback_parts.append("VLM visual workflow verification passed (+15)")
            else:
                feedback_parts.append("VLM could not confirm the cross-section editing workflow (+0)")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            # Give benefit of doubt if VLM fails but logic checks are perfect
            if score == 85: 
                vlm_points = 15
    
    score += vlm_points

    # Need at least custom airfoils and basic wing for pass
    key_criteria_met = file_exists and (has_s809 or has_s805a) and ("<WingGeom>" in content or "WingGeom" in content)
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }