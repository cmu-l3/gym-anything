#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_model_twisted_pedestal(traj, env_info, task_info):
    """
    Verifies the FreeCAD twisted pedestal task.
    
    Criteria:
    1. File exists and was created during task (15 pts)
    2. Valid FreeCAD document with at least one solid (20 pts)
    3. Geometric dimensions correct (Height ~120, Width ~80) (25 pts)
    4. Twist verified (X and Y widths are similar due to rotation) (20 pts)
    5. VLM verification of workflow/visuals (20 pts)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. File & System Checks (15 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 15
        feedback.append("File created successfully.")
    elif result.get("file_exists"):
        score += 5
        feedback.append("File exists but timestamp check failed.")
    else:
        feedback.append("Output file not found.")
        
    # 3. Geometry Analysis (65 pts total)
    geo = result.get("geometry", {})
    
    # Check Solid (20 pts)
    solid_count = geo.get("solid_count", 0)
    if solid_count > 0:
        score += 20
        feedback.append(f"Found {solid_count} solid(s).")
    else:
        feedback.append("No 3D solids found in document.")
        
    # Check Dimensions (25 pts)
    bbox = geo.get("bbox", [0, 0, 0])
    # Expecting approx 80 x 80 x 120
    # Allow tolerance of +/- 2mm
    x_ok = 78 <= bbox[0] <= 82
    y_ok = 78 <= bbox[1] <= 82
    z_ok = 118 <= bbox[2] <= 122
    
    if z_ok:
        score += 15
        feedback.append(f"Height correct ({bbox[2]:.1f}mm).")
    else:
        feedback.append(f"Height incorrect ({bbox[2]:.1f}mm, expected 120).")
        
    if x_ok and y_ok:
        score += 10
        feedback.append(f"Base/Top dimensions correct ({bbox[0]:.1f}x{bbox[1]:.1f}mm).")
        
    # Check Twist (20 pts)
    # A non-twisted hexagonal prism (point on X) would have:
    # X width = 80, Y width = 69.3
    # A twisted one (0 to 30 deg) combines extents, so Y width grows to 80.
    # We check that X and Y are close to each other (indicating rotation).
    if abs(bbox[0] - bbox[1]) < 2.0 and bbox[0] > 75:
        score += 20
        feedback.append("Twist verified (X/Y extents match).")
    elif bbox[0] > 75 and bbox[1] < 72:
        feedback.append("Geometry appears to be a straight prism (no twist detected).")

    # Volume Sanity Check (Bonus/Confirmation)
    vol = geo.get("volume", 0)
    # Prism ~498k. Twisted is slightly less. 
    if 450000 <= vol <= 510000:
        feedback.append(f"Volume valid ({vol:.0f} mm3).")
    else:
        feedback.append(f"Volume out of expected range ({vol:.0f} mm3).")

    # 4. VLM Verification (20 pts)
    # Use trajectory to confirm they actually used the tool, not just loaded a file
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames and final_screen:
        vlm_prompt = (
            "Review these screenshots of a FreeCAD modeling task. "
            "1. Do you see a hexagonal shape being sketched or manipulated? "
            "2. Do you see a twisted column or pedestal shape in the final 3D view? "
            "3. Does the object look like a single solid (not a wireframe)? "
            "Return JSON: { 'hex_sketch_visible': bool, 'twisted_shape_visible': bool }"
        )
        
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('twisted_shape_visible'):
                score += 20
                feedback.append("Visual verification passed.")
            elif parsed.get('hex_sketch_visible'):
                score += 10
                feedback.append("Sketching visible but final shape unclear.")
            else:
                feedback.append("Visual verification inconclusive.")
        else:
            # Fallback if VLM fails but geometry was perfect
            if score >= 80: 
                score += 20
                feedback.append("VLM skipped, geometry checks sufficient.")

    # Final Result
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }