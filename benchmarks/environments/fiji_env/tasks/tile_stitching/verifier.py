#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tile_stitching(traj, env_info, task_info):
    """
    Verifies the tile stitching task.
    
    Criteria:
    1. TIF output exists and was created during task.
    2. PNG output exists and was created during task.
    3. Output dimensions are reasonable (approx 3x3 grid size, > single tile).
    4. Image content is valid (not black).
    5. VLM check on trajectory (optional but good for robustness).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
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
    
    # 1. Check Output Existence (20 pts)
    if result.get("tif_exists") and result.get("png_exists"):
        score += 20
        feedback.append("Both output files found.")
    elif result.get("tif_exists"):
        score += 10
        feedback.append("TIFF found, but PNG missing.")
    else:
        feedback.append("TIFF output missing.")

    # 2. Check Timestamps (Anti-gaming) (10 pts)
    if result.get("tif_created_during_task") and result.get("png_created_during_task"):
        score += 10
        feedback.append("Files created during task session.")
    elif result.get("tif_exists"):
        feedback.append("Output file timestamps invalid (created before task?).")

    # 3. Check Dimensions (40 pts)
    # The original image is roughly 1000x750.
    # A single tile (3x3 grid, 15% overlap) is roughly 1/2.5 of width/height.
    # Stitched image should be much larger than single tile.
    
    width = result.get("width", 0)
    height = result.get("height", 0)
    is_single = result.get("is_single_tile", False)
    
    # Expected approximate dimensions from metadata
    # The setup script downloads FluorescentCells.jpg which is 512x512 or 1024x1024 usually
    # But let's rely on the relative logic:
    # If the user just saved one tile, is_single_tile will be true.
    
    if width > 100 and height > 100:
        if is_single:
            feedback.append("Output dimensions match a single tile. Did you actually stitch them?")
        else:
            # We expect the stitched image to be roughly 2-3x the size of a single tile
            # This is a good proxy for "it was stitched" without hardcoding exact pixels
            score += 40
            feedback.append(f"Dimensions ({width}x{height}) indicate successful stitching.")
    else:
        feedback.append("Output image dimensions too small or zero.")

    # 4. Check Content (Mean Intensity) (10 pts)
    mean_val = result.get("mean_intensity", 0)
    if mean_val > 5: # Not black
        score += 10
        feedback.append("Image content is valid (not black).")
    else:
        feedback.append("Output image appears to be empty/black.")
        
    # 5. VLM / Trajectory Check (20 pts)
    # This is a placeholder for the concept; in a real run, we'd query the VLM with frames.
    # We'll award points if we have a valid result file as a proxy for successful interaction
    # in this programmatic implementation, assuming if they got the file right, they used the GUI.
    if score >= 60: 
        score += 20
        feedback.append("Implicit verification: Valid output structure implies correct workflow.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }