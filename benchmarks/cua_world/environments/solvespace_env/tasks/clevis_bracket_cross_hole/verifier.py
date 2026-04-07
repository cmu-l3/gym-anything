#!/usr/bin/env python3
"""
Verifier for clevis_bracket_cross_hole task.

Uses a multi-criteria programmatic approach combined with VLM trajectory verification:
1. Validates the exported STL bounding box dimensions and total mesh volume.
2. Parses the SolveSpace .slvs file attributes to ensure a Boolean Difference operation was executed.
3. Checks file timestamps to prevent "do nothing" spoofing.
4. Uses VLM on sampled trajectory frames to visually confirm a U-bracket with a cross-hole was designed.
"""

import os
import json
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a 3D CAD modeling task in SolveSpace.
The goal of the task was to design a 'Clevis Bracket': a 3D U-shaped channel with a circular cross-hole passing completely through BOTH arms of the bracket.

Review the provided screenshots from the agent's session and the final result.
Answer the following questions:
1. Is a 3D U-shaped bracket (or channel) clearly visible in the workspace?
2. Did the agent successfully cut a circular cross-hole through the arms of the U-shape?
3. Does the hole appear to pass completely through both arms?

Provide your response as a JSON object:
{
    "u_shape_visible": true/false,
    "cross_hole_visible": true/false,
    "hole_passes_through_both_arms": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what you see in the 3D model"
}
"""

def verify_clevis_bracket(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_bbox = metadata.get('expected_bbox', [30.0, 40.0, 50.0])
    expected_vol = metadata.get('expected_volume_approx', 18715.0)
    vol_tolerance = metadata.get('volume_tolerance', 700.0)
    bbox_tolerance = metadata.get('bbox_tolerance', 1.5)

    # 1. Retrieve the task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence and Anti-Gaming Timestamps
    slvs_ok = result.get('slvs_exists', False) and result.get('slvs_created', False)
    stl_ok = result.get('stl_exists', False) and result.get('stl_created', False)
    
    if slvs_ok and stl_ok:
        score += 15
        feedback_parts.append("✅ SLVS and STL files successfully created.")
    elif slvs_ok:
        score += 10
        feedback_parts.append("⚠️ SLVS file created, but STL export missing.")
    else:
        feedback_parts.append("❌ Target files were not created.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Check for Boolean Difference Operation (.slvs analysis)
    if result.get('difference_used', False):
        score += 15
        feedback_parts.append("✅ Boolean Difference (subtraction) operation detected in .slvs file.")
    else:
        feedback_parts.append("❌ Boolean Difference operation missing (meshCombine=1 not found).")
        
    group_count = int(result.get('group_count', 0))
    if group_count >= 4: # At least: initial reference, sketch1, extrude1, sketch2, extrude2
        score += 5

    # 4. STL Geometric Analysis
    stl_analysis = result.get('stl_analysis', {})
    bbox_ok = False
    volume_ok = False
    
    if stl_analysis.get('valid', False) and stl_analysis.get('triangles', 0) >= 20:
        score += 5
        
        actual_bbox = sorted(stl_analysis.get('bbox', [0,0,0]))
        target_bbox = sorted(expected_bbox)
        
        bbox_errors = [abs(a - t) for a, t in zip(actual_bbox, target_bbox)]
        if all(e <= bbox_tolerance for e in bbox_errors):
            score += 20
            bbox_ok = True
            feedback_parts.append(f"✅ Bounding box dimensions correct (Error: max {max(bbox_errors):.2f}mm).")
        else:
            feedback_parts.append(f"❌ Bounding box dimensions incorrect. Expected ~{target_bbox}, Got {actual_bbox}.")

        actual_vol = stl_analysis.get('volume', 0.0)
        if abs(actual_vol - expected_vol) <= vol_tolerance:
            score += 20
            volume_ok = True
            feedback_parts.append(f"✅ Solid volume correct ({actual_vol:.0f} mm³).")
        elif abs(actual_vol - expected_vol) <= vol_tolerance * 3:
            score += 10
            feedback_parts.append(f"⚠️ Solid volume partially correct ({actual_vol:.0f} mm³).")
        else:
            feedback_parts.append(f"❌ Solid volume out of tolerance ({actual_vol:.0f} mm³, expected ~{expected_vol} mm³).")
    else:
        feedback_parts.append("❌ Exported STL geometry is invalid or missing triangles.")

    # 5. VLM Visual Verification
    vlm_ok = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)
            
        if frames:
            vlm_response = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("u_shape_visible") and parsed.get("cross_hole_visible"):
                    vlm_ok = True
                    score += 20
                    if parsed.get("hole_passes_through_both_arms"):
                        feedback_parts.append("✅ VLM confirmed visual accuracy of U-bracket with cross-hole through both arms.")
                    else:
                        feedback_parts.append("⚠️ VLM confirmed U-bracket and hole, but unsure if it cuts through both arms.")
                else:
                    feedback_parts.append("❌ VLM failed to identify the expected U-bracket and cross-hole.")

    # 6. Final Evaluation
    key_criteria_met = (bbox_ok or volume_ok) and (result.get('difference_used', False) or vlm_ok)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "stl_analysis": stl_analysis,
            "slvs_difference_used": result.get('difference_used', False)
        }
    }