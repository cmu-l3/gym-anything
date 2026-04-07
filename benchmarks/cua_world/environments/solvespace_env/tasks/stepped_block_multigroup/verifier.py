#!/usr/bin/env python3
"""
Verifier for stepped_block_multigroup task.

Verification Strategy:
1. File verification: Check if expected .slvs file was created/modified during task.
2. Parametric content parsing: Parse the text-based .slvs file to find constraint parameters
   and verify multiple groups (at least 4 groups: base sketch, base extrude, boss sketch, boss extrude).
3. Value checks: Extract all Param.val floats and look for the expected dimensions within tolerance.
4. VLM verification: Analyze trajectory to verify the visual process and final 3D shape.
"""

import json
import os
import re
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for verifying multi-step modeling
VLM_PROMPT = """You are evaluating an agent's performance in a CAD task using SolveSpace.
The task was to create a "stepped block": 
1. Draw a rectangular base and extrude it.
2. Sketch a smaller rectangle on the top face of that base and extrude it upward.

Look at the trajectory frames and the final screenshot.
Please answer:
1. Does the workflow show the agent sequentially sketching, extruding, then sketching on a face, and extruding again?
2. Does the final image show a 3D stepped block (a larger solid base with a smaller raised solid platform on top)?

Respond in pure JSON format:
{
    "workflow_progression_visible": true/false,
    "final_shape_is_stepped_block": true/false,
    "reasoning": "Brief explanation of what is observed in the CAD interface"
}
"""

def verify_stepped_block(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/SolveSpace/stepped_block.slvs')
    
    # Expected dimensions
    target_dims = [
        metadata.get('base_width', 80),
        metadata.get('base_height', 60),
        metadata.get('base_extrude', 20),
        metadata.get('boss_width', 40),
        metadata.get('boss_height', 30),
        metadata.get('boss_extrude', 15)
    ]
    tolerance = metadata.get('tolerance', 2.5)

    feedback = []
    score = 0
    
    # 1. Read exported result JSON
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    output_size = result.get('output_size_bytes', 0)

    # File Checks
    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file {expected_path} was not created."
        }
    
    if file_created:
        score += 10
        feedback.append("File created during task session.")
    else:
        feedback.append("Warning: File may have existed before task start (failed timestamp check).")

    if output_size > 2000:
        score += 5
        feedback.append(f"File size is valid ({output_size} bytes).")
    else:
        feedback.append(f"File size is unusually small ({output_size} bytes).")

    # 2. Parse .slvs File Content
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    slvs_content = ""
    try:
        copy_from_env(expected_path, temp_slvs.name)
        with open(temp_res.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_content = f.read()
            
        # Fallback reading directly if copy worked
        if not slvs_content:
            with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
                slvs_content = f.read()
    except Exception as e:
        logger.warning(f"Failed to read slvs file locally: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    if slvs_content:
        # Check group count (AddGroup operations)
        # Default file has 2 AddGroup lines. A single extrusion adds 1.
        # Sketch on face + Extrude adds 2 more. Expected >= 4 AddGroup occurrences.
        group_count = slvs_content.count("AddGroup")
        if group_count >= 4:
            score += 10
            feedback.append(f"Multiple modeling groups found ({group_count} total).")
        else:
            feedback.append(f"Not enough modeling groups found ({group_count}). Missing multi-step extrusions.")

        # Extract Param.val values
        param_matches = re.findall(r'Param\.val=([-\d\.]+)', slvs_content)
        found_values = [abs(float(p)) for p in param_matches if p]
        
        # Check targets
        dims_found = 0
        dims_score = 0
        for target in target_dims:
            if any(abs(v - target) <= tolerance for v in found_values):
                dims_found += 1
                dims_score += 7  # Max 42 points for all 6 dims
                
        score += dims_score
        feedback.append(f"Found {dims_found}/{len(target_dims)} expected parametric dimensions.")
    else:
        feedback.append("Could not parse SLVS content for parametric checks.")

    # 3. VLM Verification
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final_img = get_final_screenshot(traj)
        images_to_check = frames + ([final_img] if final_img else [])
        
        if images_to_check:
            try:
                vlm_res = query_vlm(prompt=VLM_PROMPT, images=images_to_check)
                if vlm_res and vlm_res.get('success') and vlm_res.get('parsed'):
                    parsed = vlm_res['parsed']
                    if parsed.get('workflow_progression_visible'):
                        vlm_score += 15
                        feedback.append("VLM: Workflow progression observed.")
                    
                    if parsed.get('final_shape_is_stepped_block'):
                        vlm_score += 18
                        feedback.append("VLM: Final 3D stepped block shape confirmed.")
                    
                    if 'reasoning' in parsed:
                        feedback.append(f"VLM Notes: {parsed['reasoning']}")
            except Exception as e:
                logger.error(f"VLM query failed: {e}")
                feedback.append("VLM verification failed to process.")

    score += vlm_score

    # Determine passing state
    # Must have the file created, multiple groups (score > 40 without VLM), and total > 65
    passed = score >= 65 and file_created and output_exists
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }