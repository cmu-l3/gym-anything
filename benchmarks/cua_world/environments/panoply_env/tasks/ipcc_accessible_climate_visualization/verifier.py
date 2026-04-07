#!/usr/bin/env python3
"""
Verifier for ipcc_accessible_climate_visualization task.

This task requires the agent to modify application-specific settings (map projection, 
central longitude, and color scale) in Panoply to create an accessibility-compliant plot.

Scoring Criteria (100 pts total, pass threshold = 70):
1. File Creation & Basic Export (20 pts): PNG and TXT exist and were created during the task.
2. Report Metadata Correctness (20 pts): The report correctly lists Robinson, 180, and a uniform scale.
3. Color Scale Programmatic Check (30 pts): Python analysis verifies the absence of pure red pixels,
   proving the agent changed away from the default rainbow palette.
4. VLM Spatial/Visual Check (30 pts): A VLM validates that the final state/exported map shows
   a Robinson (oval) projection centered on the Pacific Ocean.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if an agent correctly formatted a scientific map in NASA Panoply.

Please look at the images (which show the progression and the final map visualization).
Determine the following:
1. Is the map projection 'Robinson'? (A Robinson projection is an oval shape with flat top and bottom poles, whereas the default is a standard rectangle).
2. Is the map centered on the Pacific Ocean? (Longitude 180° means the Pacific Ocean is in the middle of the map, and the Americas are on the right/Asia is on the left).

Respond in JSON format:
{
    "is_robinson_projection": true/false,
    "is_pacific_centered": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""

def verify_ipcc_accessible_climate_visualization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from the VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/ipcc_accessible_climate_visualization_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # ----------------------------------------------------------------
    # Criterion 1: File Creation & Basic Export (20 pts)
    # ----------------------------------------------------------------
    png_exists = result.get('png_exists', False)
    png_mtime = int(result.get('png_mtime', 0))
    png_size = int(result.get('png_size', 0))
    
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))

    if png_exists and png_mtime >= task_start and png_size >= 15000:
        score += 10
        feedback.append("Standardized map plot exported correctly.")
    else:
        feedback.append("Map plot missing or invalid size/timestamp.")

    if report_exists and report_mtime >= task_start:
        score += 10
        feedback.append("Metadata report created.")
    else:
        feedback.append("Metadata report missing or invalid timestamp.")

    # ----------------------------------------------------------------
    # Criterion 2: Report Metadata Correctness (20 pts)
    # ----------------------------------------------------------------
    projection = result.get('projection_used', '')
    center_lon = result.get('center_longitude', '')
    color_scale = result.get('color_scale_used', '')
    
    allowed_scales = ['viridis', 'cividis', 'plasma', 'magma', 'inferno']
    
    meta_score = 0
    if 'robinson' in projection:
        meta_score += 7
    if '180' in center_lon:
        meta_score += 7
    if any(scale in color_scale for scale in allowed_scales):
        meta_score += 6
        
    score += meta_score
    feedback.append(f"Report Metadata Score: {meta_score}/20 (Proj: {projection}, Lon: {center_lon}, Scale: {color_scale})")

    # ----------------------------------------------------------------
    # Criterion 3: Color Scale Programmatic Check (30 pts)
    # ----------------------------------------------------------------
    has_pure_red = result.get('has_pure_red_pixels', True) # Default to true to be safe
    
    if png_exists:
        if not has_pure_red:
            score += 30
            feedback.append("Color Scale Check Passed: No pure red pixels detected (Rainbow scale successfully removed).")
        else:
            feedback.append("Color Scale Check Failed: Pure red pixels detected, indicating the default Rainbow palette may still be active.")
    else:
        feedback.append("Color Scale Check Failed: PNG missing.")

    # ----------------------------------------------------------------
    # Criterion 4: VLM Spatial/Visual Check (30 pts)
    # ----------------------------------------------------------------
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final_screen = get_final_screenshot(traj)
        
        if final_screen:
            vlm_images = frames + [final_screen]
            vlm_response = query_vlm(prompt=VERIFICATION_PROMPT, images=vlm_images)
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                is_robinson = parsed.get("is_robinson_projection", False)
                is_pacific = parsed.get("is_pacific_centered", False)
                
                vlm_score = 0
                if is_robinson:
                    vlm_score += 15
                    feedback.append("VLM confirms Robinson projection.")
                else:
                    feedback.append("VLM did not detect Robinson projection.")
                    
                if is_pacific:
                    vlm_score += 15
                    feedback.append("VLM confirms Pacific-centric map.")
                else:
                    feedback.append("VLM did not detect Pacific-centric map.")
                    
                score += vlm_score
            else:
                feedback.append(f"VLM query failed: {vlm_response.get('error')}")
        else:
            feedback.append("VLM Check Failed: No final screenshot available.")
    else:
        feedback.append("VLM Check Skipped: VLM not available.")

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    # Require files to be created + key features verified to pass
    passed = (score >= 70) and png_exists and report_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }