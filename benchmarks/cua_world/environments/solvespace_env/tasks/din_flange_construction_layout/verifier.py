#!/usr/bin/env python3
"""
Verifier for din_flange_construction_layout task.

Verifies:
1. File exists and was created during the task.
2. The file contains Construction Geometry (Entity.construction=1).
3. The file contains an Extrusion group (Group.type=5012).
4. The file contains the expected parametric dimensions (allow for radius/diameter).
5. VLM confirms the 3D topology (flange with central hole and 4 bolt holes).
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt
VERIFICATION_PROMPT = """You are verifying if an AI agent successfully modeled a 3D pipe flange in SolveSpace.

Look at these screenshots from the modeling process and the final state.
Determine:
1. Is there a 3D solid model visible? (Not just a 2D flat sketch)
2. Is the overall shape a circular disc/cylinder?
3. Does it have one large central hole (bore)?
4. Does it have exactly 4 smaller bolt holes arranged in a ring around the center?

Respond in JSON format:
{
    "has_3d_solid": true/false,
    "is_circular_disc": true/false,
    "has_central_hole": true/false,
    "has_4_bolt_holes": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what you see"
}
"""

def verify_flange_model(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Read the JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result.get("output_exists", False)
    file_created_during_task = result.get("file_created_during_task", False)
    
    if not output_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file dn50_flange.slvs was not found."
        }
        
    if file_created_during_task:
        score += 10
        feedback_parts.append("File created/modified during task")
    else:
        feedback_parts.append("Warning: File timestamp indicates it might not be newly created")

    # Read the SLVS file
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    slvs_text = ""
    try:
        copy_from_env("/tmp/dn50_flange.slvs", temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_text = f.read()
    except Exception as e:
        feedback_parts.append(f"Failed to read SLVS file: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    if not slvs_text:
        return {"passed": False, "score": score, "feedback": "SLVS file is empty or unreadable."}

    # Verify Construction Geometry
    if "Entity.construction=1" in slvs_text:
        score += 25
        feedback_parts.append("Construction geometry detected")
    else:
        feedback_parts.append("Missing construction geometry")

    # Verify Extrusion Group (SolveSpace extrude type is 5012)
    if "Group.type=5012" in slvs_text or "Group.type=5002" in slvs_text:
        score += 15
        feedback_parts.append("Extrusion group detected")
    else:
        feedback_parts.append("No extrusion group detected")

    # Verify Parametric Dimensions
    param_vals = []
    for line in slvs_text.split('\n'):
        if 'Param.val=' in line:
            try:
                val = float(line.split('=')[1].strip())
                param_vals.append(val)
            except ValueError:
                pass
                
    # Dimensions to check (allow diameter or radius)
    expected_dims = {
        "Outer (165 or 82.5)": [165.0, 82.5],
        "Pitch (125 or 62.5)": [125.0, 62.5],
        "Inner (61 or 30.5)": [61.0, 30.5],
        "Holes/Thickness (18 or 9)": [18.0, 9.0]
    }
    
    dims_found = 0
    tolerance = 0.5
    for dim_name, valid_vals in expected_dims.items():
        found = any(min(abs(p - v) for v in valid_vals) <= tolerance for p in param_vals)
        if found:
            dims_found += 1
            
    if dims_found == len(expected_dims):
        score += 25
        feedback_parts.append("All expected DIN dimensions found")
    elif dims_found > 0:
        partial = (dims_found / len(expected_dims)) * 25
        score += partial
        feedback_parts.append(f"Found {dims_found}/{len(expected_dims)} dimensions")
    else:
        feedback_parts.append("Expected dimensions not found")

    # VLM Verification
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        frames = sample_trajectory_frames(traj, n=3)
        final_frame = get_final_screenshot(traj)
        
        if final_frame:
            images = frames + [final_frame]
            vlm_res = query_vlm(prompt=VERIFICATION_PROMPT, images=images)
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                vlm_score = 0
                
                if parsed.get("has_3d_solid"): vlm_score += 10
                if parsed.get("is_circular_disc"): vlm_score += 5
                if parsed.get("has_central_hole"): vlm_score += 5
                if parsed.get("has_4_bolt_holes"): vlm_score += 5
                
                score += vlm_score
                feedback_parts.append(f"VLM verified visual topology ({vlm_score}/25 pts)")
            else:
                feedback_parts.append("VLM visual verification failed to execute")
    else:
        feedback_parts.append("VLM query function not available")

    passed = score >= 70 and "Construction geometry detected" in feedback_parts and output_exists
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }