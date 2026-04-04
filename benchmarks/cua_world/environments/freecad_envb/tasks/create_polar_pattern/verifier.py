#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_polar_pattern(traj, env_info, task_info):
    """
    Verifies the NEMA 23 motor flange creation task.
    
    Criteria:
    1. File exists and valid (10 pts)
    2. Body and Pad exist (20 pts)
    3. Pocket exists (10 pts)
    4. Polar Pattern exists (15 pts) - CRITICAL for this task
    5. Dimensions (BBox) correct (15 pts)
    6. Volume correct (indicates holes are present) (15 pts)
    7. VLM verification of workflow (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_vol = metadata.get('expected_volume_mm3', 7960.0)
    vol_tolerance = metadata.get('volume_tolerance', 0.15)
    
    # Copy result JSON
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

    score = 0
    feedback = []
    
    # 1. File Check
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not result.get("file_created_during_task", False):
        feedback.append("⚠️ File timestamp indicates it wasn't created during this session.")
    else:
        score += 10
        feedback.append("✅ File created.")

    # 2. Geometry Analysis
    geo = result.get("geometry_analysis", {})
    
    if geo.get("valid_doc"):
        # Body & Pad
        if geo.get("has_body") and geo.get("has_pad"):
            score += 20
            feedback.append("✅ Body and Pad feature found.")
        else:
            feedback.append("❌ Missing Body or Pad feature.")
            
        # Pocket
        if geo.get("has_pocket"):
            score += 10
            feedback.append("✅ Pocket feature found.")
        else:
            feedback.append("❌ Missing Pocket feature.")
            
        # Polar Pattern
        if geo.get("has_polar_pattern"):
            score += 15
            feedback.append("✅ PolarPattern feature found.")
        else:
            feedback.append("❌ PolarPattern feature MISSING.")
            
        # Dimensions (BBox)
        bbox = geo.get("bbox", [0, 0, 0])
        # Expected: ~60, ~60, ~5
        if abs(bbox[0] - 60) < 3 and abs(bbox[1] - 60) < 3 and abs(bbox[2] - 5) < 1:
            score += 15
            feedback.append(f"✅ Dimensions correct ({bbox[0]:.1f}x{bbox[1]:.1f}x{bbox[2]:.1f}mm).")
        else:
            feedback.append(f"❌ Dimensions incorrect: {bbox[0]:.1f}x{bbox[1]:.1f}x{bbox[2]:.1f}mm (Expected 60x60x5).")
            
        # Volume
        vol = geo.get("volume", 0)
        # Check if volume matches (Solid disc is ~14137, correct part is ~7960)
        # If volume is too high, they didn't make holes.
        if expected_vol * (1 - vol_tolerance) <= vol <= expected_vol * (1 + vol_tolerance):
            score += 15
            feedback.append(f"✅ Volume correct ({vol:.0f} mm³).")
        elif vol > 13000:
             feedback.append(f"❌ Volume too high ({vol:.0f} mm³). Holes likely missing.")
        else:
             feedback.append(f"❌ Volume incorrect ({vol:.0f} mm³).")

    else:
        feedback.append("❌ Invalid or corrupted FreeCAD document.")

    # 3. VLM Verification
    # Use trajectory to ensure they actually used the tools and didn't just load a file (though file timestamp helps there)
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a FreeCAD session.
    The user is supposed to:
    1. Create a circular sketch.
    2. Pad it to make a disc.
    3. Make holes (pockets).
    4. Use a 'Polar Pattern' to array the bolt holes around the center.
    
    Do you see evidence of:
    - A circular flange shape?
    - A pattern of holes (4 holes)?
    - The usage of the 'PolarPattern' tool or icon in the history/tree?
    
    Answer JSON with boolean 'flange_visible', 'holes_visible', 'pattern_tool_used'.
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt).get("parsed", {})
        
        vlm_score = 0
        if vlm_res.get("flange_visible", False): vlm_score += 5
        if vlm_res.get("holes_visible", False): vlm_score += 5
        if vlm_res.get("pattern_tool_used", False): vlm_score += 5
        
        score += vlm_score
        feedback.append(f"✅ VLM visual verification score: {vlm_score}/15")
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        # Grant partial credit on failure to avoid punishing API errors if file is good
        if score > 50: 
            score += 10
            feedback.append("⚠️ VLM check skipped (API error), added partial credit.")

    return {
        "passed": score >= 60 and geo.get("has_polar_pattern", False),
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }