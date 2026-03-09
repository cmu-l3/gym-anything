#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_architectural_frame(traj, env_info, task_info):
    """
    Verify the creation of an architectural frame in FreeCAD.
    Checks for file existence, correct object types (Arch::Structure), roles (Column/Beam),
    and geometric properties (dimensions/placement) extracted from the file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Helper to load JSON from container
    def load_json_from_container(remote_path):
        local_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        local_temp.close()
        try:
            copy_from_env(remote_path, local_temp.name)
            with open(local_temp.name, 'r') as f:
                return json.load(f)
        except Exception:
            return None
        finally:
            if os.path.exists(local_temp.name):
                os.unlink(local_temp.name)

    # Load basic result info
    task_result = load_json_from_container("/tmp/task_result.json")
    if not task_result:
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result"}

    score = 0
    feedback_parts = []
    
    # 1. File Existence (10 pts)
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file structural_frame.FCStd not found."}
    
    score += 10
    feedback_parts.append("File created")

    # Load detailed analysis (extracted by freecadcmd inside container)
    analysis = load_json_from_container("/tmp/structural_analysis.json")
    if not analysis or analysis.get("error"):
        return {"passed": False, "score": score, "feedback": f"File created, but failed to parse geometry: {analysis.get('error') if analysis else 'Unknown error'}"}

    objects = analysis.get("objects", [])
    
    # Filter objects by Role
    columns = [o for o in objects if o.get("role") == "Column"]
    beams = [o for o in objects if o.get("role") == "Beam"]
    axes = analysis.get("axes", [])
    
    # 2. Axis System (10 pts)
    if len(axes) > 0:
        score += 10
        feedback_parts.append("Axis system present")
    else:
        feedback_parts.append("Missing Axis/Grid")

    # 3. Columns Verification (45 pts total)
    # Quantity & Type (20 pts)
    if len(columns) == 4:
        score += 20
        feedback_parts.append("Correct column count (4)")
    else:
        feedback_parts.append(f"Incorrect column count: {len(columns)}/4")
        score += min(len(columns) * 5, 15) # Partial credit

    # Dimensions (15 pts)
    col_dim_ok = 0
    for col in columns:
        bbox = col.get("bbox", {})
        # Check 200x200x3000 (allowing rotation, so just check sorted dims)
        dims = sorted([bbox.get("x_len", 0), bbox.get("y_len", 0), bbox.get("z_len", 0)])
        # Expected: ~200, ~200, ~3000
        if (190 <= dims[0] <= 210) and (190 <= dims[1] <= 210) and (2990 <= dims[2] <= 3010):
            col_dim_ok += 1
            
    if len(columns) > 0:
        score += int(15 * (col_dim_ok / len(columns)))
        if col_dim_ok == len(columns):
            feedback_parts.append("Column dimensions correct")
        else:
            feedback_parts.append(f"Column dimensions issue ({col_dim_ok}/{len(columns)} ok)")

    # Position (10 pts)
    # Check if they are at Z=0
    col_pos_ok = sum(1 for c in columns if abs(c["placement"]["z"]) < 1.0)
    if len(columns) > 0:
        score += int(10 * (col_pos_ok / len(columns)))

    # 4. Beams Verification (35 pts total)
    # Quantity & Type (15 pts)
    if len(beams) == 2:
        score += 15
        feedback_parts.append("Correct beam count (2)")
    else:
        feedback_parts.append(f"Incorrect beam count: {len(beams)}/2")
        score += min(len(beams) * 7, 14)

    # Position (20 pts) - Must be at Z=3000 (top of columns)
    beam_pos_ok = 0
    for beam in beams:
        # Check Z height (either via placement or bounding box min Z)
        z_min = beam.get("bbox", {}).get("z_min", -1)
        z_placement = beam["placement"]["z"]
        
        # Accept if placement is ~3000 OR if the geometry starts at ~3000
        if (2900 <= z_placement <= 3100) or (2900 <= z_min <= 3100):
            beam_pos_ok += 1
            
    if len(beams) > 0:
        score += int(20 * (beam_pos_ok / len(beams)))
        if beam_pos_ok == len(beams):
            feedback_parts.append("Beam elevations correct")
        else:
            feedback_parts.append("Beam elevation incorrect (should be on top of columns)")

    # 5. VLM Verification (Bonus/Confirmation)
    # Only if score is borderline or for sanity check
    # Check for visual confirmation of grid structure
    if score > 50:
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            vlm_res = query_vlm(
                prompt="Is there a 3D structural frame visible with vertical columns and horizontal beams? Answer yes or no.",
                image=final_screenshot
            )
            if vlm_res.get("success") and "yes" in vlm_res.get("response", "").lower():
                # Just confirms, no extra points unless we want to split points
                pass
            else:
                feedback_parts.append("(Visual check uncertain)")

    passed = score >= 70 and len(columns) >= 4 and len(beams) >= 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }