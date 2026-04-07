#!/usr/bin/env python3
"""
Verifier for oring_piston_step_export task in SolveSpace.

VERIFICATION METRICS:
1. File Checks (20 pts): SLVS and STEP files created during task.
2. Export Validity (15 pts): STEP file contains valid ISO-10303-21 header.
3. SolveSpace Modeling (15 pts): Native .slvs file contains a Lathe/Revolve group (`Group.type=5200`).
4. Dimensions (20 pts): Extracts parameter constraints looking for 50, 40 (or 20), 4, 3, 10, etc.
5. VLM Verification (30 pts): Trajectory frames show the agent working on a cylindrical profile and using export menus.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM prompt for visual verification
VERIFICATION_PROMPT = """You are verifying a CAD modeling task in SolveSpace.
The goal was to design a cylindrical piston (height 50mm, diameter 40mm) with an O-ring groove (4mm wide, 3mm deep) near the top, and then export it as a STEP file.

Review the provided trajectory frames and the final screenshot.
Did the agent accomplish the following:
1. Draw a profile (either a half-profile or a cut profile) representing the stepped piston geometry?
2. Use the Revolve/Lathe tool (or Extrude + Difference) to generate a 3D cylindrical shape with a radial groove?
3. Apply dimensional constraints to the sketch?
4. Open the File -> Export 3D menu/dialog to export the model?

Return JSON with these boolean fields and a reasoning string:
{
    "drew_profile": true/false,
    "revolved_3d_shape_visible": true/false,
    "applied_constraints": true/false,
    "attempted_export": true/false,
    "reasoning": "string"
}
"""

def verify_oring_piston(traj, env_info, task_info):
    """Verify piston modeling and STEP export."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    
    try:
        # Copy JSON result
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
        # Copy SLVS file
        copy_from_env("/tmp/agent_piston_groove.slvs", temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_text = f.read()
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result files: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    # 1. File existence and anti-gaming (20 points)
    slvs_ok = result.get('slvs_exists', False) and result.get('slvs_created_during_task', False)
    step_ok = result.get('step_exists', False) and result.get('step_created_during_task', False)
    
    if slvs_ok:
        score += 10
        feedback_parts.append("SLVS model saved")
    else:
        feedback_parts.append("SLVS missing or stale")
        
    if step_ok:
        score += 10
        feedback_parts.append("STEP export saved")
    else:
        feedback_parts.append("STEP export missing or stale")

    # 2. STEP Export Validity (15 points)
    step_header = result.get('step_header', '')
    if step_ok and 'ISO-10303-21' in step_header:
        score += 15
        feedback_parts.append("Valid STEP file format")
    elif step_ok:
        feedback_parts.append("Invalid STEP file header")

    # 3. SolveSpace Modeling Check - Revolve/Lathe Group (15 points)
    # SolveSpace entity types: 5100=Extrude, 5200=Lathe, 5300=Assemble
    has_lathe = "Group.type=5200" in slvs_text
    has_extrude = "Group.type=5100" in slvs_text
    
    if has_lathe:
        score += 15
        feedback_parts.append("Revolve operation detected")
    elif has_extrude:
        # Give partial credit if they just extruded but failed to cut the groove via revolve
        score += 5
        feedback_parts.append("Extrude detected but Revolve missing")
    elif slvs_ok and len(slvs_text) > 100:
        feedback_parts.append("No 3D solid groups detected")

    # 4. Dimensional Constraints Check (20 points)
    # Parse parameter values (e.g., Param.val=50.0000)
    params = re.findall(r"Param\.val=([0-9\.-]+)", slvs_text)
    params_float = []
    for p in params:
        try:
            params_float.append(float(p))
        except:
            pass
            
    matched_dims = 0
    # Expected approximate targets (absolute value matching):
    # Height 50, Outer 40 or 20, Groove Width 4, Groove Depth 3, Offset 10, Inner 34 or 17
    target_values = [50.0, 40.0, 20.0, 4.0, 3.0, 10.0, 34.0, 17.0]
    
    for tv in target_values:
        if any(abs(abs(p) - tv) < 0.05 for p in params_float):
            matched_dims += 1
            
    if matched_dims >= 4:
        score += 20
        feedback_parts.append(f"Parametric dimensions matched ({matched_dims} found)")
    elif matched_dims > 0:
        score += (matched_dims * 4)
        feedback_parts.append(f"Partial parametric dimensions matched ({matched_dims} found)")
    elif slvs_ok:
        feedback_parts.append("Required dimensional constraints missing")

    # 5. VLM Trajectory Verification (30 points)
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_result = query_vlm(prompt=VERIFICATION_PROMPT, images=images)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    drew_profile = parsed.get("drew_profile", False)
                    revolved_3d = parsed.get("revolved_3d_shape_visible", False)
                    applied_constraints = parsed.get("applied_constraints", False)
                    attempted_export = parsed.get("attempted_export", False)
                    
                    if drew_profile and applied_constraints:
                        score += 10
                        feedback_parts.append("VLM: Sketching confirmed")
                    if revolved_3d:
                        score += 10
                        feedback_parts.append("VLM: 3D geometry confirmed")
                    if attempted_export:
                        score += 10
                        feedback_parts.append("VLM: Export workflow confirmed")
                else:
                    feedback_parts.append("VLM query failed")
            else:
                feedback_parts.append("No screenshots for VLM")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append("VLM processing error")
    else:
        # Fallback if VLM not available
        score += 30
        feedback_parts.append("VLM unavailable (points awarded automatically)")

    # Final scoring
    # Key criteria: Must have successfully made a 3D part and exported it
    key_criteria_met = (slvs_ok and step_ok and has_lathe)
    passed = (score >= 65 and key_criteria_met)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "slvs_size": result.get('slvs_size_bytes', 0),
            "step_size": result.get('step_size_bytes', 0),
            "matched_dims": matched_dims
        }
    }