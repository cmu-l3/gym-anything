#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_packaging_die_cut(traj, env_info, task_info):
    """
    Verifies the packaging die-line task.
    
    Strategy:
    1. File Check: DXF exists and was created during the task.
    2. DXF Analysis (pre-computed in container): 
       - Check for layers 'CUT' (Red) and 'FOLD' (Blue).
       - Check for specific geometric entities (creases, chamfers).
    3. VLM Verification:
       - Visually confirm the drawing looks like a box net.
       - Confirm usage of two distinct colors.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Basic File Checks (10 points)
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "DXF file was not saved to expected location."}
    
    score += 5
    if result.get("file_created_during_task", False):
        score += 5
        feedback.append("File created during task.")
    else:
        feedback.append("Warning: File timestamp indicates it wasn't modified during task.")

    # 2. DXF Structure Analysis (50 points)
    analysis = result.get("dxf_analysis", {})
    if not analysis.get("valid_dxf", False):
        return {"passed": False, "score": score, "feedback": "Saved file is not a valid DXF."}

    layers = analysis.get("layers", {})
    
    # Check CUT Layer (Red=1)
    if "CUT" in layers:
        score += 10
        if layers["CUT"]["color"] == 1:
            score += 5
            feedback.append("Layer 'CUT' exists and is Red.")
        else:
            feedback.append(f"Layer 'CUT' exists but color is {layers['CUT']['color']} (expected 1/Red).")
    else:
        feedback.append("Layer 'CUT' missing.")

    # Check FOLD Layer (Blue=5)
    if "FOLD" in layers:
        score += 10
        if layers["FOLD"]["color"] == 5:
            score += 5
            feedback.append("Layer 'FOLD' exists and is Blue.")
        else:
            feedback.append(f"Layer 'FOLD' exists but color is {layers['FOLD']['color']} (expected 5/Blue).")
    else:
        feedback.append("Layer 'FOLD' missing.")

    # Check Geometry Count (20 points)
    geo = analysis.get("geometry_check", {})
    
    # We expect roughly 4 vertical fold lines + 2 horizontal fold lines = 6-10 distinct lines
    # depending on how they drew it (polylines vs lines).
    if geo.get("fold_lines", 0) >= 4:
        score += 10
        feedback.append("Sufficient fold lines detected.")
    else:
        feedback.append("Not enough fold lines detected.")

    if geo.get("glue_tab_chamfer", False):
        score += 10
        feedback.append("Glue tab chamfer detected.")
    else:
        feedback.append("Glue tab chamfer NOT detected.")

    # 3. VLM Visual Verification (40 points)
    # The programmatic check is strict on layer names, but VLM checks the "look".
    
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    if final_screenshot:
        prompt = """
        You are verifying a CAD drawing of a packaging box net (die-line).
        Check for the following:
        1. Is there a drawing of 4 rectangular panels side-by-side?
        2. Are there flaps on the top and bottom?
        3. Are there lines of two different colors (Red and Blue/Green)?
        4. Does the geometry look like a flat layout of a box?
        
        Answer JSON: {"is_box_net": bool, "has_two_colors": bool, "has_flaps": bool}
        """
        try:
            vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
            parsed = vlm_res.get("parsed", {})
            
            if parsed.get("is_box_net", False):
                vlm_score += 20
                feedback.append("VLM confirms shape looks like a box net.")
            if parsed.get("has_two_colors", False):
                vlm_score += 10
                feedback.append("VLM confirms multi-colored lines.")
            if parsed.get("has_flaps", False):
                vlm_score += 10
                feedback.append("VLM confirms flaps present.")
                
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback.append("VLM verification failed.")
            # Fallback points if programmatic was perfect
            if score >= 50:
                 vlm_score += 20
    
    total_score = score + vlm_score
    passed = total_score >= 75
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }