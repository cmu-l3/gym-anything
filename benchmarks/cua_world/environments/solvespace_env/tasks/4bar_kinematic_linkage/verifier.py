#!/usr/bin/env python3
"""Verifier for 4-bar kinematic linkage task in SolveSpace."""

import os
import json
import tempfile
import logging
from typing import Dict, Any
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_4bar_kinematic_linkage(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_file = metadata.get('output_file', '/home/ga/Documents/SolveSpace/kinematic_linkage.slvs')
    exp_crank = metadata.get('expected_crank_mm', 18.0)
    exp_rocker = metadata.get('expected_rocker_mm', 32.0)
    exp_ground = metadata.get('expected_ground_mm', 55.0)
    exp_coupler = metadata.get('expected_coupler_mm', 64.0)

    # Copy task result from export script
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    file_exists = result.get("output_exists", False)
    file_created = result.get("file_created_during_task", False)

    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Output file kinematic_linkage.slvs not found."}

    score += 10
    feedback.append("File exists")

    if file_created:
        score += 10
        feedback.append("File created during task")
    else:
        feedback.append("File was NOT created/modified during task")

    found_crank, found_rocker, found_ground, found_coupler = False, False, False, False

    # Copy the actual SLVS file to check constraint values (SolveSpace plain text file structure)
    slvs_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env(expected_output_file, slvs_temp.name)
        with open(slvs_temp.name, 'r') as f:
            content = f.read()

        # Extract all Param.val=... floats
        param_vals = []
        for line in content.split('\n'):
            line = line.strip()
            if line.startswith('Param.val='):
                try:
                    val = float(line.split('=')[1])
                    param_vals.append(val)
                except ValueError:
                    pass

        # Check for constraint dimensions with slight float tolerance
        found_crank = any(abs(v - exp_crank) < 0.1 for v in param_vals)
        found_rocker = any(abs(v - exp_rocker) < 0.1 for v in param_vals)
        found_ground = any(abs(v - exp_ground) < 0.1 for v in param_vals)
        found_coupler = any(abs(v - exp_coupler) < 0.1 for v in param_vals)

        if found_crank:
            score += 10
            feedback.append(f"Crank constraint ({exp_crank}mm) found")
        else:
            feedback.append(f"Crank constraint ({exp_crank}mm) missing")

        if found_rocker:
            score += 10
            feedback.append(f"Rocker constraint ({exp_rocker}mm) found")
        else:
            feedback.append(f"Rocker constraint ({exp_rocker}mm) missing")

        if found_ground:
            score += 10
            feedback.append(f"Ground constraint ({exp_ground}mm) found")
        else:
            feedback.append(f"Ground constraint ({exp_ground}mm) missing")

        if found_coupler:
            score += 10
            feedback.append(f"Coupler constraint ({exp_coupler}mm) found")
        else:
            feedback.append(f"Coupler constraint ({exp_coupler}mm) missing")

    except Exception as e:
        feedback.append(f"Error parsing .slvs file: {e}")
    finally:
        if os.path.exists(slvs_temp.name):
            os.unlink(slvs_temp.name)

    # VLM Verification
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = f"""You are verifying if an agent successfully created a 4-bar kinematic linkage in SolveSpace.
Look at these screenshots from the agent's trajectory.
1. Is there a 4-bar linkage visible (4 connected line segments forming a closed loop quadrilateral)?
2. Are the dimensions {exp_crank}, {exp_rocker}, {exp_ground}, and {exp_coupler} visible on the canvas?
3. Are the segments connected end-to-end?

Respond in JSON format:
{{
    "has_4bar_loop": true/false,
    "dimensions_visible": true/false,
    "connected": true/false
}}
"""
        try:
            vlm_result = query_vlm(images=images, prompt=prompt)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("has_4bar_loop"):
                    score += 15
                    feedback.append("VLM: 4-bar loop visible")
                if parsed.get("dimensions_visible"):
                    score += 10
                    feedback.append("VLM: Dimensions visible")
                if parsed.get("connected"):
                    score += 5
                    feedback.append("VLM: Segments appear connected")
            else:
                feedback.append("VLM verification failed or unavailable")
        except Exception as e:
            feedback.append(f"VLM error: {e}")

    # To pass: Required file conditions + programmatic constraints must be met + passing score
    passed = file_exists and file_created and found_crank and found_rocker and found_ground and found_coupler and score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }