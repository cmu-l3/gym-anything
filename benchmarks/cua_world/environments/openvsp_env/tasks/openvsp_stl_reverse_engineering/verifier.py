#!/usr/bin/env python3
"""
Verifier for openvsp_stl_reverse_engineering task.

Scoring Criteria (100 points total):
1. Model saved, created during session, and valid XML (10 pts)
2. MeshGeom component present (proves STL was imported) (15 pts)
3. Parameter accuracy (50 points total, 10 pts each):
   - Span within tolerance
   - Root Chord within tolerance
   - Tip Chord within tolerance
   - Sweep within tolerance
   - Dihedral within tolerance
4. VLM Trajectory Verification: Proves agent actually worked visually (25 pts)

Pass threshold: 60 points with STL imported and key parameters aligned.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM prompt to ensure the agent actually aligned the meshes visually in OpenVSP
VLM_PROMPT = """You are evaluating an agent performing a reverse-engineering CAD task in OpenVSP.
The goal was to import a 3D-scanned STL wing mesh and overlay a new parametric Wing component to match it.

Review these trajectory frames and determine:
1. Is the OpenVSP software open and active?
2. Did the agent successfully import an external mesh (usually appears as a distinct gray/unstructured triangulated shape)?
3. Did the agent add a parametric Wing component and adjust its dimensions (span, chord, sweep)?
4. Is there evidence that the agent visually overlaid or worked with BOTH the mesh and the parametric wing in the 3D view at some point?

Respond in JSON format:
{
    "openvsp_active": true/false,
    "mesh_imported": true/false,
    "wing_adjusted": true/false,
    "worked_with_both": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation"
}
"""

def _extract_param_values(content: str, tag: str) -> list:
    """Extract all Value attributes for a given XML tag."""
    pattern = rf'<{tag}\s+Value="([^"]+)"'
    vals = []
    for m in re.finditer(pattern, content):
        try:
            vals.append(float(m.group(1)))
        except ValueError:
            pass
    return vals

def verify_stl_reverse_engineering(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "/tmp/openvsp_stl_reverse_engineering_result.json")
    
    # Expected truth values
    e_span = metadata.get("expected_span", 10.0)
    e_root = metadata.get("expected_root_chord", 2.0)
    e_tip = metadata.get("expected_tip_chord", 1.0)
    e_sweep = metadata.get("expected_sweep", 5.0)
    e_dihedral = metadata.get("expected_dihedral", 3.0)
    tolerance = metadata.get("tolerance_percent", 10) / 100.0

    # Retrieve output JSON
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result file: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []
    
    # 1. File existence and anti-gaming
    file_exists = data.get("file_exists", False)
    created_during_task = data.get("created_during_task", False)
    content = data.get("file_content", "").replace("\\n", "\n")

    if not file_exists:
        return {
            "passed": False, "score": 0,
            "feedback": "reconstructed_wing.vsp3 not found. The agent did not save the model."
        }
    
    if not created_during_task:
        feedback_parts.append("Warning: File timestamp indicates it was not modified during the task.")
    else:
        try:
            ET.fromstring(content)
            score += 10
            feedback_parts.append("Valid model saved during session (+10).")
        except ET.ParseError:
            feedback_parts.append("Saved model is not valid XML (+0).")

    # 2. Check for MeshGeom (did they actually import the STL?)
    mesh_present = "<TypeName>MeshGeom</TypeName>" in content or "MeshGeom" in content
    if mesh_present:
        score += 15
        feedback_parts.append("MeshGeom found (STL successfully imported) (+15).")
    else:
        feedback_parts.append("MeshGeom NOT found. The STL was not imported! (+0).")

    # 3. Check WingGeom parameters
    def check_param(tag, expected, points, name):
        nonlocal score
        vals = _extract_param_values(content, tag)
        if not vals:
            feedback_parts.append(f"{name} parameter not found (+0).")
            return
        
        # Check if any value is within the acceptable range
        margin = expected * tolerance if expected != 0 else tolerance
        for v in vals:
            if abs(v - expected) <= margin:
                score += points
                feedback_parts.append(f"{name} matches target ({v:.2f} ≈ {expected}) (+{points}).")
                return
        
        best = min(vals, key=lambda x: abs(x - expected))
        feedback_parts.append(f"{name} is {best:.2f}, target was {expected} (+0).")

    check_param("TotalSpan", e_span, 10, "Span")
    check_param("Root_Chord", e_root, 10, "Root Chord")
    check_param("Tip_Chord", e_tip, 10, "Tip Chord")
    check_param("Sweep", e_sweep, 10, "Sweep")
    check_param("Dihedral", e_dihedral, 10, "Dihedral")

    # 4. VLM Trajectory Verification
    vlm_points_earned = 0
    query_fn = env_info.get('query_vlm')
    
    if query_fn:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images_to_check = frames + ([final_frame] if final_frame else [])
            
            if images_to_check:
                vlm_result = query_fn(prompt=VLM_PROMPT, images=images_to_check)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    vlm_criteria = sum([
                        parsed.get("openvsp_active", False),
                        parsed.get("mesh_imported", False),
                        parsed.get("wing_adjusted", False),
                        parsed.get("worked_with_both", False)
                    ])
                    # Proportional out of 25 pts
                    vlm_points_earned = int((vlm_criteria / 4) * 25)
                    score += vlm_points_earned
                    feedback_parts.append(f"VLM Visual verification: {vlm_points_earned}/25 pts.")
                else:
                    feedback_parts.append(f"VLM verification failed: {vlm_result.get('error')}.")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append(f"VLM verification encountered error.")
    else:
        feedback_parts.append("VLM unavailable - skipping visual check.")

    # Determine pass state
    passed = score >= 60 and mesh_present
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }