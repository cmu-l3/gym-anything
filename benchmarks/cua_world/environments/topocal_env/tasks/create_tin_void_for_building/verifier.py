#!/usr/bin/env python3
"""
Verifier for Create Terrain Void for Building Footprint task in TopoCal.

Verification Strategy:
1. Ensure the output DXF file exists and was created after the task started.
2. Ensure the DXF contains the exported 3D Faces (terrain triangles).
3. Validate that NO triangles exist inside the building bounding box.
4. Validate that surrounding triangles exist (agent didn't just delete everything).
5. Review trajectory frames via VLM to confirm the software workflow was used.
"""

import os
import json
import tempfile
import logging
import subprocess
import sys

# Ensure ezdxf is available for spatial DXF parsing
try:
    import ezdxf
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "ezdxf"])
    import ezdxf

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent using TopoCal (a topographic CAD software).
The agent was tasked with creating a Digital Terrain Model (TIN) and deleting the triangles inside a building footprint.

Review these trajectory frames and determine:
1. Did the agent successfully import points and generate a triangulated terrain mesh?
2. Is there visual evidence of the agent interacting with the surface/MDT editing tools (like deleting triangles or creating boundaries)?
3. Does the final state show a visible "hole" or void in the triangulated terrain mesh?

Respond in JSON format:
{
    "mesh_generated": true/false,
    "editing_tools_used": true/false,
    "visible_void_created": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def verify_create_tin_void(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Fatal: Copy function not available"}

    metadata = task_info.get('metadata', {})
    bounds_x = metadata.get('building_bounds_x', [500100, 500120])
    bounds_y = metadata.get('building_bounds_y', [4400100, 4400130])
    
    score = 0
    feedback = []

    # 1. Retrieve the Task Execution Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve execution data: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result_data.get('output_exists', False)
    output_mtime = result_data.get('output_mtime', 0)
    task_start = result_data.get('task_start', 0)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "DXF output file was not created."}

    if output_mtime < task_start:
        feedback.append("Warning: DXF file appears to be from before the task started (anti-gaming).")
    else:
        score += 20
        feedback.append("File created successfully during task.")

    # 2. Retrieve and Parse the DXF
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\terrain_with_void.dxf", temp_dxf.name)
        
        try:
            doc = ezdxf.readfile(temp_dxf.name)
            msp = doc.modelspace()
            faces = msp.query('3DFACE')
            total_faces = len(faces)
            
            if total_faces > 0:
                score += 20
                feedback.append(f"Exported TIN successfully ({total_faces} triangles found).")
            else:
                feedback.append("DXF exists but contains no 3D faces/terrain.")
                
            # Spatial analysis of the triangles
            faces_inside = 0
            faces_outside = 0
            
            for face in faces:
                # 3DFACE has 4 vertices (vtx3 equals vtx2 for triangles)
                pts = [face.dxf.vtx0, face.dxf.vtx1, face.dxf.vtx2, face.dxf.vtx3]
                cx = sum(p.x for p in pts) / 4.0
                cy = sum(p.y for p in pts) / 4.0
                
                # Check if centroid falls inside the building bounding box
                # We use a small epsilon tolerance buffer (0.5m) to prevent floating point boundary edge-cases
                if (bounds_x[0] - 0.5) <= cx <= (bounds_x[1] + 0.5) and \
                   (bounds_y[0] - 0.5) <= cy <= (bounds_y[1] + 0.5):
                    faces_inside += 1
                else:
                    faces_outside += 1

            # Integrity score: Ensure they didn't just delete the whole map
            if faces_outside > 100:
                score += 20
                feedback.append(f"Terrain integrity preserved ({faces_outside} external triangles).")
            elif faces_outside > 0:
                score += 10
                feedback.append(f"Partial terrain integrity ({faces_outside} external triangles).")
            else:
                feedback.append("Error: Surrounding terrain was destroyed.")

            # Goal score: Verify the void
            if total_faces > 0 and faces_outside > 50:
                if faces_inside == 0:
                    score += 40
                    feedback.append("Perfect Void: 0 triangles exist inside the building footprint!")
                else:
                    feedback.append(f"Failed to clear void: {faces_inside} triangles found inside building footprint.")

        except Exception as dxf_e:
            feedback.append(f"DXF Parsing Error: {dxf_e}")

    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    # 3. Trajectory VLM Verification (Optional cross-check)
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if frames and final:
            vlm_res = query_vlm(images=frames + [final], prompt=VLM_PROMPT)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("visible_void_created"):
                    feedback.append("VLM confirms visible terrain void in the workspace.")
                else:
                    feedback.append("VLM could not confirm visible void.")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    # Determine Pass/Fail
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }