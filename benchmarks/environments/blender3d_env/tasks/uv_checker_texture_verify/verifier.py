#!/usr/bin/env python3
"""
Verifier for UV Checker Texture task.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_uv_checker(traj, env_info, task_info):
    """
    Verify UV unwrap and Checker Texture application.
    
    Criteria:
    1. Blend file saved & modified (15 pts)
    2. UV layer exists on Suzanne (15 pts)
    3. UV coverage is adequate (non-degenerate) (15 pts)
    4. Checker Texture node exists (15 pts)
    5. Checker node connected to Base Color (15 pts)
    6. Render output exists and is valid (15 pts)
    7. VLM/Visual check of render (10 pts)
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Load result JSON
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback_parts = []
    
    # --- Check 1: Blend File (15 pts) ---
    if result.get("blend_file_exists") and result.get("blend_file_valid"):
        if result.get("blend_modified_after_start"):
            score += 15
            feedback_parts.append("Blend file saved")
        else:
            score += 5
            feedback_parts.append("Blend file exists but not modified")
    else:
        feedback_parts.append("No blend file")
        
    # --- Check 2: UV Layer (15 pts) ---
    uv_count = result.get("suzanne_uv_layer_count", 0)
    if uv_count > 0:
        score += 15
        feedback_parts.append(f"UV layer found ({uv_count})")
    else:
        feedback_parts.append("No UV layers")
        
    # --- Check 3: UV Coverage (15 pts) ---
    coverage = result.get("uv_coverage_ratio", 0.0)
    if coverage > 0.15: # Reasonable coverage for a head unwrap
        score += 15
        feedback_parts.append(f"UV coverage good ({coverage:.2f})")
    elif coverage > 0.0:
        score += 5
        feedback_parts.append(f"UV coverage poor ({coverage:.2f})")
    else:
        feedback_parts.append("UVs are degenerate/empty")
        
    # --- Check 4: Checker Node (15 pts) ---
    if result.get("has_checker_node"):
        score += 15
        feedback_parts.append("Checker node found")
    else:
        feedback_parts.append("No Checker node")
        
    # --- Check 5: Connection (15 pts) ---
    if result.get("checker_connected_to_base_color"):
        score += 15
        feedback_parts.append("Node connected")
    elif result.get("has_checker_node"):
        feedback_parts.append("Checker node not connected to Base Color")
        
    # --- Check 6: Render Output (15 pts) ---
    if result.get("render_file_exists") and result.get("render_file_size_kb", 0) > 10:
        if result.get("render_modified_after_start"):
            score += 15
            feedback_parts.append("Render saved")
        else:
            score += 5
            feedback_parts.append("Render exists but old")
    else:
        feedback_parts.append("No render output")
        
    # --- Check 7: VLM Visual Verification (10 pts) ---
    # We check the final render for the checker pattern
    vlm_score = 0
    if query_vlm and result.get("render_file_exists"):
        # We need to get the actual render image from the container
        # Since we can't easily copy binary files to memory here without temp files,
        # we rely on the final screenshot or attempt to copy the render.
        # Ideally, we verify the render file itself.
        
        try:
            temp_render = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            temp_render.close()
            copy_from_env(metadata.get("expected_render_path", "/home/ga/BlenderProjects/checker_render.png"), temp_render.name)
            
            prompt = """
            Look at this rendered image of a 3D monkey head.
            1. Is there a monkey head visible?
            2. Is there a checkerboard (grid) pattern mapped onto the surface of the head?
            3. Are the checkers relatively square and evenly distributed (indicating good UVs)?
            
            Respond JSON: {"monkey_visible": bool, "checker_pattern_visible": bool, "good_uv_distribution": bool}
            """
            
            vlm_out = query_vlm(prompt=prompt, images=[temp_render.name])
            if vlm_out.get("success"):
                parsed = vlm_out.get("parsed", {})
                if parsed.get("checker_pattern_visible"):
                    vlm_score = 10
                    feedback_parts.append("Visual check passed")
                else:
                    feedback_parts.append("Visual check failed (no checkers)")
            
            os.unlink(temp_render.name)
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            
    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }