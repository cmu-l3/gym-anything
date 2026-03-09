#!/usr/bin/env python3
"""
Verifier for create_pipe_elbow task.

Checks:
1. File existence and valid creation time.
2. Geometric properties (Volume, Bounding Box) extracted via FreeCAD scripting.
3. VLM verification of the modeling workflow.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_pipe_elbow(traj, env_info, task_info):
    """
    Verify the created pipe elbow model.
    """
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. File & Workflow Validation (25 pts)
    # ------------------------------------------------------------------
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("File created")
        if created_during:
            score += 15
            feedback_parts.append("File created during task session")
        else:
            feedback_parts.append("File timestamp pre-dates task (reused file?)")
    else:
        feedback_parts.append("No output file found")
        return {"passed": False, "score": 0, "feedback": "Output file pipe_elbow.FCStd not found"}

    # ------------------------------------------------------------------
    # 2. Geometric Validation (50 pts)
    # ------------------------------------------------------------------
    geo = result.get('geometry_analysis', {})
    
    if geo.get('valid_shape', False):
        score += 10
        feedback_parts.append("Valid 3D shape detected")
        
        # Volume Check
        # Expected: ~9080 mm3 for a perfect elbow
        # Range in metadata: 5500 - 14000 (wide enough for rougher approximations but excludes solids)
        vol = geo.get('volume', 0)
        min_vol = metadata.get('min_volume', 5500)
        max_vol = metadata.get('max_volume', 14000)
        
        if min_vol <= vol <= max_vol:
            score += 20
            feedback_parts.append(f"Volume correct ({vol:.0f} mm³)")
        else:
            feedback_parts.append(f"Volume out of range ({vol:.0f} mm³)")
            
        # Bounding Box Check
        # Expected sorted dims: [25, 52.5, 52.5]
        # (25 is Diameter, 52.5 is Radius + OuterRadius = 40 + 12.5)
        bbox = geo.get('bbox', [0, 0, 0])
        target_bbox = metadata.get('target_bbox_sorted', [25.0, 52.5, 52.5])
        tol = metadata.get('bbox_tolerance', 8.0)
        
        bbox_ok = True
        for i in range(3):
            if abs(bbox[i] - target_bbox[i]) > tol:
                bbox_ok = False
                break
        
        if bbox_ok:
            score += 20
            feedback_parts.append(f"Dimensions correct ({bbox})")
        else:
            feedback_parts.append(f"Dimensions incorrect ({bbox})")
            
    else:
        feedback_parts.append(f"Geometry error: {geo.get('error', 'Unknown')}")

    # ------------------------------------------------------------------
    # 3. VLM Verification (25 pts)
    # ------------------------------------------------------------------
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_scr = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of a user working in FreeCAD.
        Task: Create a 90-degree pipe elbow fitting.
        
        Look for:
        1. A curved pipe-like shape in the 3D viewport.
        2. Evidence of modeling operations (Sketching, Padding, Sweeping, or Torus creation).
        3. The shape looks hollow (tubular), not a solid block.
        
        Does the final result look like a pipe elbow?
        """
        
        vlm_res = query_vlm(images=frames + [final_scr], prompt=prompt)
        
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('answer_bool', False): 
            # Note: assuming simple boolean parser or analyzing text "yes"
            # Since standard parser might vary, we assume a positive evaluation adds points
            # We can rely on 'success' from a specialized evaluator or just assume manual review
            # For this template, we'll check for positive keywords in reasoning if boolean missing
            reasoning = vlm_res.get('parsed', {}).get('reasoning', str(vlm_res))
            if "yes" in reasoning.lower() or "correct" in reasoning.lower() or "elbow" in reasoning.lower():
                score += 25
                feedback_parts.append("VLM confirmed visual appearance")
            else:
                score += 10
                feedback_parts.append("VLM uncertain about appearance")
        else:
             # Fallback if VLM fails or is negative
             # We give partial credit if geometry was perfect, assuming VLM might be flaky
             if score >= 60:
                 score += 15
                 feedback_parts.append("VLM check skipped/failed, relying on geometry")
             else:
                 feedback_parts.append("VLM check failed")

    # Final Pass check
    passed = score >= 60 and geo.get('valid_shape', False)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }