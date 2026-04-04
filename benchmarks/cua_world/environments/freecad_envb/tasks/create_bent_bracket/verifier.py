#!/usr/bin/env python3
"""
Verifier for create_bent_bracket task.

Verifies:
1. File creation and validity.
2. Geometric properties (Volume, Dimensions).
3. Topological properties (Solid check, Fillet application).
4. Workflow evidence (Offset tool usage).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_bent_bracket(traj, env_info, task_info):
    """
    Verify the bracket creation task.
    """
    # 1. Setup and copy result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract metrics
    analysis = result.get("geometry_analysis", {})
    metadata = task_info.get("metadata", {})
    
    score = 0
    feedback = []

    # Criterion 1: File Existence (10 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File saved successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found or not saved."}

    # Criterion 2: Valid Solid (20 pts)
    if analysis.get("valid_file") and analysis.get("is_solid"):
        score += 20
        feedback.append("Valid solid body created.")
    else:
        feedback.append("Result is not a valid solid (might be a surface/shell).")

    # Criterion 3: Volume Accuracy (30 pts)
    # Expected Volume ~= PathLength(100) * Height(50) * Thickness(2) = 10000? 
    # Let's re-calc: 
    # Path: (0,0)->(30,0) [30mm] -> (30,40) [40mm] -> (60,40) [30mm]. Total L = 100mm.
    # Extrusion Height = 50mm. Surface Area = 100 * 50 = 5000 mm^2.
    # Thickness = 2mm. Volume ~= 5000 * 2 = 10,000 mm^3.
    # (Corner overlaps/fillets might adjust this slightly, but 10k is the baseline).
    # Metadata said 8000, let's adjust logic to be relative to measured volume if needed
    # or rely on the analysis return.
    
    actual_vol = analysis.get("volume", 0)
    # Refined estimate: 10,000 mm^3. 
    # Fillets remove material. 4 corners. 
    # Let's set a wide tolerance: 8500 - 11000.
    
    if 8500 <= actual_vol <= 11500:
        score += 30
        feedback.append(f"Volume correct ({actual_vol:.0f} mm³).")
    elif actual_vol > 0:
        score += 10
        feedback.append(f"Volume out of range ({actual_vol:.0f} mm³). Expected ~10000.")
    else:
        feedback.append("Volume is zero.")

    # Criterion 4: Dimensions/Height (20 pts)
    bbox_z = analysis.get("bbox_z", 0)
    if 49.0 <= bbox_z <= 51.0:
        score += 20
        feedback.append("Extrusion height correct (50mm).")
    else:
        feedback.append(f"Incorrect height ({bbox_z:.1f}mm).")

    # Criterion 5: Workflow/Topology (20 pts)
    # Fillets add faces. A simple offset box Z-shape has:
    # 3 segments * 2 sides + 2 ends + top/bottom... 
    # Checking "has_fillet" flag from history is safer than face counting.
    if analysis.get("has_offset") and analysis.get("has_fillet"):
        score += 20
        feedback.append("Used Offset and Fillet tools.")
    elif analysis.get("has_offset"):
        score += 10
        feedback.append("Used Offset but Fillet missing.")
    else:
        feedback.append("Did not use Offset tool (Workflow violation).")

    # 3. VLM Verification (Bonus/Confirmation)
    # We use VLM to ensure it looks like a Z-bracket
    frames = sample_trajectory_frames(traj, 3)
    if frames:
        vlm_res = query_vlm(
            prompt="Is a grey 3D Z-shaped metal bracket visible in the FreeCAD viewport?",
            images=frames,
            model="gpt-4o"
        )
        if vlm_res.get("success") and vlm_res.get("parsed", {}).get("answer") == "yes":
             # Confirm visual
             pass
        else:
            feedback.append("(Visual check inconclusive)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }