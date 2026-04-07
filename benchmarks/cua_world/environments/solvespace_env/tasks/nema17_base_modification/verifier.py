#!/usr/bin/env python3
"""
Verifier for nema17_base_modification task.

Uses a multi-signal approach to prevent gaming:
1. Verifies the file was created during the task timespan.
2. Parses the underlying plaintext .slvs format to find expected parameter values (dimensions).
3. Parses the .slvs file to ensure a Boolean difference (cut) group was added to the base file.
4. Uses the Vision Language Model (VLM) on trajectory frames to visually verify the 5-hole pattern.
"""
import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nema17_base_modification(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Retrieve & Check File Output Data 
    # ================================================================
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

    slvs_exists = result.get('slvs_exists', False)
    stl_exists = result.get('stl_exists', False)
    file_created = result.get('file_created_during_task', False)
    stl_size = result.get('stl_size_bytes', 0)

    if not slvs_exists:
        return {"passed": False, "score": 0, "feedback": "Required output SLVS file missing. Task failed."}
    if not file_created:
        return {"passed": False, "score": 0, "feedback": "File exists but timestamps prove it wasn't modified during task (anti-gaming)."}

    score += 10
    feedback_parts.append("SLVS file created")

    if stl_exists and stl_size > 500:
        score += 10
        feedback_parts.append("Valid STL export exists")
    else:
        feedback_parts.append("STL missing or suspiciously small")

    # ================================================================
    # 2. Programmatic .slvs File Parsing (Verify exact CAD parameters)
    # ================================================================
    has_cut = False
    has_dims = False
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    
    try:
        copy_from_env("/tmp/nema17_base.slvs", temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_content = f.read()

        # Check for Boolean Difference (cutting)
        if "Group.boolean=1" in slvs_content:
            has_cut = True
            score += 20
            feedback_parts.append("Boolean cut detected in file")
        else:
            feedback_parts.append("No boolean Difference cut found in SLVS structure")

        # Extract all parameters to check NEMA 17 specification
        # E.g., looking for Param.val=22.20000000
        params = [float(x) for x in re.findall(r'Param\.val=([0-9\.\-]+)', slvs_content)]
        
        def has_param(target, tol=0.05):
            return any(abs(p - target) <= tol for p in params)
        
        # Check against diameters OR radii since agent might constrain either
        center_ok = has_param(22.2) or has_param(11.1)
        mount_ok = has_param(3.2) or has_param(1.6)
        spacing_ok = has_param(31.04) or has_param(15.52)
        
        dim_score = 0
        if center_ok: dim_score += 1
        if mount_ok: dim_score += 1
        if spacing_ok: dim_score += 1

        if dim_score >= 2:
            has_dims = True
            score += 20
            feedback_parts.append(f"Parametric dimensions matched ({dim_score}/3)")
        else:
            feedback_parts.append(f"Dimensions missing/incorrect (Matched {dim_score}/3)")

    except Exception as e:
        feedback_parts.append(f"Failed to parse SLVS internals: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    # ================================================================
    # 3. Trajectory-Based VLM Verification
    # ================================================================
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            prompt = """You are verifying a CAD modification task in SolveSpace.
The agent was asked to open an existing plate part, create a new sketch on its flat face, draw a NEMA 17 motor mount pattern (1 large center circle, 4 smaller corner circles in a square array), and extrude-cut the holes entirely through the plate.

Examine these trajectory frames and determine:
1. Did the agent sketch multiple circles on the 3D plate?
2. Is there clear visual evidence of a 5-hole pattern (1 center, 4 corners)?
3. Were these holes cut completely through the geometry?

Respond STRICTLY in JSON format:
{
    "pattern_sketched": true/false,
    "holes_cut": true/false,
    "reasoning": "brief explanation"
}"""
            vlm_result = query_vlm(images=images, prompt=prompt)
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("pattern_sketched") and parsed.get("holes_cut"):
                    score += 40
                    feedback_parts.append("VLM confirms 5-hole pattern and cut operation")
                elif parsed.get("pattern_sketched"):
                    score += 20
                    feedback_parts.append("VLM confirms sketch, but hole cut is missing/incomplete")
                else:
                    feedback_parts.append("VLM did not detect the expected NEMA 17 pattern workflow")

    # ================================================================
    # 4. Final Aggregation
    # ================================================================
    key_criteria_met = has_cut and has_dims
    passed = score >= 70 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }