#!/usr/bin/env python3
"""
Verifier for vector_polygon_masking_envi task.

Scoring breakdown (100 total points):
  - ENVI Format export present & generated during task:  20 pts
  - Spectral bands preserved (>= 3 bands):               20 pts
  - Vector Spatial Masking achieved mathematically:      30 pts (partial 15 for crop only)
  - VLM: Verified Vector Imported from trajectory:       15 pts
  - VLM: Verified Masking Execution from trajectory:     15 pts

Pass Threshold: 70
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_TRAJECTORY_PROMPT = """You are assessing a sequence of screenshots from an agent interacting with ESA SNAP Desktop. 

The task involves:
1. Opening a satellite image.
2. Importing an ESRI Shapefile representing a wildlife reserve boundary.
3. Applying a spatial mask to the image using the imported Shapefile (e.g., Land/Sea Mask, Vector subset).
4. Exporting to ENVI format.

Carefully evaluate the sequence and reply with JSON assessing these exact criteria:
1. "vector_imported": True if there is evidence of the Shapefile being imported or visible in the UI (e.g., 'reserve_boundary' layer appearing in the Product Explorer, or a diamond vector outline visible on the image canvas).
2. "masking_executed": True if there is evidence of the agent configuring or executing a masking operation using the vector polygon (e.g., the 'Land/Sea Mask' dialog is open, or a spatial subset dialog restricted by the vector is open, or a resulting masked product is seen).

Ensure your output matches this format exactly:
{
    "vector_imported": true/false,
    "masking_executed": true/false,
    "reasoning": "explain your observations"
}
"""

def verify_vector_polygon_masking(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/vector_masking_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # 1. ENVI format check (20 pts)
    if result.get('envi_found') and result.get('envi_created_after_start'):
        score += 20
        feedback.append("ENVI file exported successfully (+20)")
    elif result.get('envi_found'):
        score += 10
        feedback.append("ENVI file found but timestamp indicates it might be old (+10)")
    else:
        feedback.append("No ENVI file found (0/20)")

    # 2. Spectral Band Integrity Check (20 pts)
    bands = result.get('band_count', 0)
    if bands >= 3:
        score += 20
        feedback.append(f"Spectral bands preserved: {bands} bands (+20)")
    elif bands > 0:
        score += 10
        feedback.append(f"Only {bands} bands found in output (+10)")
    else:
        feedback.append("Failed to parse valid bands from ENVI header (0/20)")

    # 3. Vector Spatial Masking Math (30 pts)
    # The diamond vector takes up exactly 32% of the original image area.
    # Its bounding box takes up exactly 64% of the original image area.
    # Masking ratio computes Valid Pixels / Total Pixels in the *exported* file.
    ratio = result.get('masking_ratio', 1.0)
    
    if 0.25 <= ratio <= 0.55:
        # Either masked over the full image (~32%) OR subset to bounds and masked (~50%)
        score += 30
        feedback.append(f"Excellent vector spatial masking confirmed (Valid pixel ratio: {ratio:.2f}) (+30)")
    elif 0.55 < ratio <= 0.75:
        # Agent just cropped to the bounding box of the vector (~64%) but didn't mask the exterior
        score += 15
        feedback.append(f"Partial masking: Image cropped to bounding box but polygon exterior not masked (Ratio: {ratio:.2f}) (+15)")
    else:
        feedback.append(f"Spatial masking not applied correctly (Valid pixel ratio: {ratio:.2f}) (0/30)")

    # 4. VLM Trajectory Check (30 pts)
    vlm_points = 0
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    if 'query_vlm' in env_info:
        query_vlm = env_info['query_vlm']
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        try:
            vlm_response = query_vlm(prompt=VLM_TRAJECTORY_PROMPT, images=frames)
            if vlm_response.get("success"):
                vlm_data = vlm_response.get("parsed", {})
                
                if vlm_data.get("vector_imported", False):
                    score += 15
                    vlm_points += 15
                    feedback.append("VLM: Vector import visible (+15)")
                else:
                    feedback.append("VLM: No evidence of vector import (0/15)")
                    
                if vlm_data.get("masking_executed", False):
                    score += 15
                    vlm_points += 15
                    feedback.append("VLM: Masking configuration visible (+15)")
                else:
                    feedback.append("VLM: No evidence of masking configuration (0/15)")
            else:
                feedback.append("VLM verification failed to parse")
        except Exception as e:
            feedback.append(f"VLM verification error: {e}")
    else:
        # Gracefully handle missing VLM by inferring UI intent if mathematical masking was perfect
        if ratio <= 0.55 and bands >= 3:
            score += 30
            feedback.append("VLM absent but strict mathematical evidence implies successful UI workflow (+30)")
        else:
            feedback.append("VLM unavailable to verify workflow UI steps (0/30)")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}