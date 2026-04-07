#!/usr/bin/env python3
"""
Verifier for boolean_difference_hole task.

Validates the `.slvs` CAD file structure to ensure boolean difference
operations were correctly applied and queries a VLM with trajectory images.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if a CAD agent successfully created a 3D part with a hole.
Look at the sequence of images (the workflow) and the final result.

The goal was: Create a 3D rectangular plate with a circular through-hole using a boolean "Difference" extrusion.

Please determine:
1. Does the final image show a 3D solid rectangular block?
2. Is there a visible circular hole cut through the block?
3. Are there any visible error dialogs, crash messages, or red constraint failure warnings?

Respond strictly in JSON format:
{
    "shows_3d_plate": true,
    "shows_hole": true,
    "has_errors": false,
    "reasoning": "brief explanation"
}
"""

def verify_boolean_difference(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    file_exists = result.get("file_exists", False)
    file_modified = result.get("file_modified_during_task", False)
    
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file not found. Task failed."
        }
    
    score += 10
    feedback_parts.append("File exists")
    
    if file_modified:
        score += 5
        feedback_parts.append("File modified during task")
    else:
        feedback_parts.append("Warning: File not modified during task (Possible Do-Nothing)")

    # 2. Parse the SLVS file structural definitions
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    slvs_content = ""
    try:
        copy_from_env("/tmp/mounting_plate.slvs", temp_slvs.name)
        with open(temp_slvs.name, 'r') as f:
            slvs_content = f.read()
    except Exception as e:
        logger.warning(f"Could not read SLVS file: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)
            
    # File syntax analysis
    valid_format = "SolveSpaceREVa" in slvs_content
    has_difference = False
    
    if valid_format:
        score += 5
        feedback_parts.append("Valid SolveSpace format")
        
        # Check base extrusion
        has_extrusion = "Group.type=5100" in slvs_content
        if has_extrusion:
            score += 15
            feedback_parts.append("Extrusion group found")
            
        # Check boolean difference (meshCombine=1 denotes difference mode)
        has_difference = "Group.meshCombine=1" in slvs_content
        if has_difference:
            score += 25
            feedback_parts.append("Boolean difference applied (meshCombine=1)")
        else:
            feedback_parts.append("No boolean difference found (missing meshCombine=1)")
            
        # Check multiple sketch groups
        sketch_groups = slvs_content.count("Group.type=5000") + slvs_content.count("Group.type=5001")
        if sketch_groups >= 2:
            score += 10
            feedback_parts.append(f"Multiple sketch groups ({sketch_groups})")
            
        # Check circle entity (Request.type=400)
        has_circle = "Request.type=400" in slvs_content
        if has_circle:
            score += 10
            feedback_parts.append("Circle entity found")
    else:
        feedback_parts.append("Invalid or empty SolveSpace file")

    # 3. VLM Trajectory Verification
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            
            if final:
                images = frames + [final] if frames else [final]
                vlm_result = query_vlm(images=images, prompt=VERIFICATION_PROMPT)
                
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    shows_3d_plate = parsed.get("shows_3d_plate", False)
                    shows_hole = parsed.get("shows_hole", False)
                    has_errors = parsed.get("has_errors", True)
                    
                    if shows_3d_plate and shows_hole:
                        vlm_score += 15
                        feedback_parts.append("VLM confirms 3D plate with hole")
                    elif shows_3d_plate:
                        vlm_score += 5
                        feedback_parts.append("VLM sees plate, but no hole")
                    else:
                        feedback_parts.append("VLM did not verify 3D hole")
                        
                    if not has_errors:
                        vlm_score += 5
                        feedback_parts.append("No visible errors")
                    else:
                        feedback_parts.append("Errors visible in UI")
                else:
                    feedback_parts.append(f"VLM query failed: {vlm_result.get('error', 'unknown')}")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append("VLM check skipped due to error")
            
    score += vlm_score
    
    # Passing condition: At least 60 points, the file must be modified, AND the meshCombine=1 operation must exist
    passed = (score >= 60) and file_modified and has_difference
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }