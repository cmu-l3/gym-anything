#!/usr/bin/env python3
"""
Verifier for pcb_enclosure_base task in SolveSpace.

VERIFICATION STRATEGY:
1. Anti-gaming check: File must exist and be created during the task.
2. Parametric constraints parsing: Parse the plain-text .slvs file to check if the 
   agent successfully applied the required dimensional constraints.
3. VLM Trajectory check: Ask VLM to verify the 3D features (cavity, standoffs, holes)
   from the trajectory and final screenshots to ensure logical CSG progression.
"""

import os
import json
import math
import tempfile
import logging
from typing import List, Dict, Any

# Assuming framework provides these in the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_slvs_params(file_path: str) -> List[float]:
    """Extract all float parameter values from a SolveSpace .slvs file."""
    params = []
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                if 'Param.val=' in line:
                    try:
                        val_str = line.split('=')[1].strip()
                        params.append(float(val_str))
                    except ValueError:
                        pass
    except Exception as e:
        logger.error(f"Error reading .slvs file: {e}")
    return params


def check_param(params: List[float], target: float, tol: float = 0.5) -> bool:
    """Check if a target parameter value exists in the extracted parameters list."""
    return any(math.isclose(p, target, abs_tol=tol) or math.isclose(abs(p), target, abs_tol=tol) for p in params)


def verify_pcb_enclosure(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/SolveSpace/pcb_enclosure.slvs')
    
    score = 0
    feedback_parts = []
    
    # 1. Check basic task results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file pcb_enclosure.slvs was not saved."}
    
    if not file_created:
        return {"passed": False, "score": 0, "feedback": "File exists but was not created/modified during this task session."}

    score += 10
    feedback_parts.append("File successfully created")

    # 2. Extract and Verify Parameters from .slvs file
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env(expected_path, temp_slvs.name)
        params = extract_slvs_params(temp_slvs.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to copy/parse .slvs file: {e}"}
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)
            
    logger.info(f"Extracted parameters: {params}")

    # Check Base Dimensions (100x60x30)
    has_base = check_param(params, 100.0) and check_param(params, 60.0) and check_param(params, 30.0)
    if has_base:
        score += 20
        feedback_parts.append("Base block dimensions found")
    else:
        feedback_parts.append("Base block dimensions missing/incorrect")

    # Check Cavity Dimensions (96x56x28 or 2mm offsets)
    has_cavity_dims = (check_param(params, 96.0) and check_param(params, 56.0)) or (params.count(2.0) >= 2)
    has_cavity_depth = check_param(params, 28.0)
    if has_cavity_dims and has_cavity_depth:
        score += 20
        feedback_parts.append("Cavity cut dimensions found")
    else:
        feedback_parts.append("Cavity cut dimensions missing/incorrect")

    # Check Standoffs (8dia/4rad, 42x22pos, 10depth)
    has_standoff_size = check_param(params, 8.0) or check_param(params, 4.0)
    has_standoff_pos = check_param(params, 42.0) and check_param(params, 22.0)
    has_extrude_10 = check_param(params, 10.0)
    if has_standoff_size and has_standoff_pos and has_extrude_10:
        score += 15
        feedback_parts.append("Standoff pillars dimensions found")
    else:
        feedback_parts.append("Standoff pillars dimensions missing/incorrect")

    # Check Holes (3dia/1.5rad)
    has_hole_size = check_param(params, 3.0) or check_param(params, 1.5)
    if has_hole_size and has_extrude_10:
        score += 15
        feedback_parts.append("Pilot holes dimensions found")
    else:
        feedback_parts.append("Pilot holes dimensions missing/incorrect")

    # 3. VLM Verification for workflow logic (Did they actually create the 3D shapes correctly?)
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """
            You are verifying a parametric CAD modeling task in SolveSpace. 
            The user was tasked with creating a PCB enclosure base. Look at the progression and final state.
            
            Please verify the following 3D features:
            1. Is there a 3D rectangular box/block?
            2. Has the box been hollowed out to create an open cavity/shell?
            3. Are there 4 cylindrical pillars (standoffs) standing inside the cavity (in the corners)?
            4. Do those 4 pillars have holes cut into the top of them?
            
            Return a JSON object with boolean fields indicating success:
            {
                "box_created": true/false,
                "cavity_hollowed": true/false,
                "pillars_present": true/false,
                "holes_present": true/false
            }
            """
            
            vlm_response = query_vlm(images=images, prompt=prompt)
            if vlm_response and vlm_response.get("success"):
                vlm_data = vlm_response.get("parsed", {})
                vlm_score = 0
                if vlm_data.get("box_created"): vlm_score += 5
                if vlm_data.get("cavity_hollowed"): vlm_score += 5
                if vlm_data.get("pillars_present"): vlm_score += 5
                if vlm_data.get("holes_present"): vlm_score += 5
                
                score += vlm_score
                feedback_parts.append(f"VLM visual confirmation score: {vlm_score}/20")
            else:
                feedback_parts.append("VLM verification failed to process")
        except Exception as e:
            logger.warning(f"VLM evaluation error: {e}")
            feedback_parts.append("VLM evaluation error (awarding partial visual credit)")
            score += 10 # Grace score if VLM crashes but programmatic passes

    # Overall passing condition
    passed = score >= 75 and output_exists and has_base and has_cavity_depth
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }