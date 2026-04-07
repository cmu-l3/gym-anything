#!/usr/bin/env python3
"""
Verifier for omega_pipe_strap_bracket task.

Verification Strategy:
1. Anti-gaming: Check that file was created after task start.
2. Geometry counts: Parse SLVS to ensure 2 arcs and >=8 lines exist.
3. Modeling logic: Ensure an extrude group exists.
4. Parameter accuracy: Parse SLVS to find the presence of exact required dimensions (20, 25, 5, 30).
5. VLM validation: Use trajectory frames to confirm the 3D omega shape was formed.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_omega_pipe_strap(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_file = metadata.get('expected_output_file', '/home/ga/Documents/SolveSpace/pipe_strap.slvs')
    
    score = 0
    feedback_parts = []
    
    # =========================================================================
    # 1. Check basic execution properties (JSON result)
    # =========================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file not found. Task not completed."}
    if not file_created:
        return {"passed": False, "score": 0, "feedback": "Output file was not created during the task (do-nothing detected)."}
        
    score += 10
    feedback_parts.append("File created successfully (10 pts)")
    
    # =========================================================================
    # 2. Parse SLVS File Content Programmatically
    # =========================================================================
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env(expected_file, temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read SLVS file: {e}"}
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)
            
    # Count structural entities
    lines_count = slvs_content.count("Entity.type=11000")
    arcs_count = slvs_content.count("Entity.type=20000") + slvs_content.count("Entity.type=20001")
    extrude_count = slvs_content.count("Group.type=5100")
    
    if lines_count >= 8:
        score += 15
        feedback_parts.append(f"Found sufficient lines ({lines_count}) (15 pts)")
    else:
        feedback_parts.append(f"Insufficient lines (found {lines_count}, expected >=8)")
        
    if arcs_count >= 2:
        score += 15
        feedback_parts.append(f"Found sufficient arcs ({arcs_count}) (15 pts)")
    else:
        feedback_parts.append(f"Insufficient arcs (found {arcs_count}, expected >=2)")
        
    if extrude_count >= 1:
        score += 15
        feedback_parts.append("Extrude group found (15 pts)")
    else:
        feedback_parts.append("No extrude group found")
        
    # Check parameters/dimensions
    vals = []
    for line in slvs_content.split('\n'):
        if "val=" in line:
            try:
                v = float(line.split("val=")[1].strip())
                vals.append(v)
            except ValueError:
                pass
                
    # Function to check if a target dimension exists in the solver values
    def has_val(target, tolerance=0.1):
        return any(abs(abs(v) - target) <= tolerance for v in vals)
        
    params_found = 0
    if has_val(20.0): params_found += 1
    if has_val(25.0): params_found += 1
    if has_val(5.0): params_found += 1
    if has_val(30.0): params_found += 1
    
    score += params_found * 5
    feedback_parts.append(f"Found {params_found}/4 required dimensions ({params_found * 5} pts)")
    
    # =========================================================================
    # 3. VLM Trajectory Verification
    # =========================================================================
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        # Filter None and assemble
        images = [img for img in frames + [final] if img is not None]
        
        prompt = """Look at these frames of a user working in SolveSpace parametric CAD.
Did the user successfully create an "omega" shaped pipe strap bracket?
Check for the following criteria:
1. Is there a 3D extruded solid shape visible?
2. Does the shape have a central semi-circular arch (consisting of two concentric arcs)?
3. Does the shape have two flat horizontal mounting flanges extending on either side of the arch?

Return JSON format strictly:
{
    "is_3d_extruded": true/false,
    "has_central_arch": true/false,
    "has_mounting_flanges": true/false,
    "reasoning": "brief explanation"
}"""
        try:
            vlm_response = query_vlm(images=images, prompt=prompt)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                if parsed.get("is_3d_extruded"): vlm_score += 10
                if parsed.get("has_central_arch"): vlm_score += 10
                if parsed.get("has_mounting_flanges"): vlm_score += 5
                
                feedback_parts.append(f"VLM verification: {vlm_score}/25 pts ({parsed.get('reasoning', 'No reasoning provided')})")
            else:
                feedback_parts.append("VLM evaluation failed or returned invalid format")
        except Exception as e:
            feedback_parts.append(f"VLM evaluation error: {e}")
            
    score += vlm_score
    
    # Evaluation Pass Threshold
    key_criteria_met = file_created and lines_count >= 8 and arcs_count >= 2 and extrude_count >= 1
    passed = score >= 70 and key_criteria_met
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }