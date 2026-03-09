#!/usr/bin/env python3
"""
Verifier for Baseball Infield Layout task.
Uses the pre-calculated DXF analysis from the container + VLM verification.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_baseball_infield_layout(traj, env_info, task_info):
    """
    Verifies the baseball infield layout task.
    
    Scoring Breakdown:
    1. File creation (10pts)
    2. Correct Layers (10pts)
    3. Geometric Constraints (via ezdxf analysis in container) (50pts)
    4. VLM Verification (Visual correctness) (30pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON from container
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
    
    # 2. Check File Stats
    if result.get("output_exists") and result.get("file_created_during_task"):
        score += 10
        feedback.append("DXF file created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "No new DXF file generated."}

    # 3. Check DXF Analysis (Geometry)
    analysis = result.get("dxf_analysis", {})
    if not analysis.get("valid_dxf"):
        return {"passed": False, "score": score, "feedback": "File is not a valid DXF."}

    # Layers check
    required_layers = ["FOUL_LINES", "BASES", "MOUND", "MARKINGS", "DIMENSIONS"]
    found_layers = analysis.get("layers_found", [])
    missing_layers = [l for l in required_layers if l not in found_layers]
    
    if not missing_layers:
        score += 10
        feedback.append("All required layers present.")
    else:
        score += max(0, 10 - (len(missing_layers) * 2))
        feedback.append(f"Missing layers: {', '.join(missing_layers)}.")

    # Geometry checks
    if analysis.get("foul_lines_ok"):
        score += 20
        feedback.append("Foul lines correctly positioned.")
    else:
        feedback.append("Foul lines missing or incorrect angles.")

    # Bases check (expect 3 bases at correct distances)
    bases_found = analysis.get("bases_found", 0)
    if bases_found >= 3:
        score += 15
        feedback.append(f"Found {bases_found} bases at correct distances.")
    elif bases_found > 0:
        score += 5 * bases_found
        feedback.append(f"Found only {bases_found}/3 bases.")
    else:
        feedback.append("No bases found at correct locations.")

    # Pitcher's plate
    if analysis.get("pitcher_plate_ok"):
        score += 15
        feedback.append("Pitcher's plate correctly positioned.")
    
    # 4. VLM Verification (Visual)
    # Use final screenshot to confirm it "looks" like a baseball field
    final_img = get_final_screenshot(traj)
    if final_img:
        vlm_prompt = (
            "You are grading a CAD drawing of a baseball infield. "
            "Look for: "
            "1. A diamond shape formed by bases. "
            "2. Two diagonal foul lines forming a V-shape (90 degrees total). "
            "3. A pitcher's mound/plate in the center. "
            "4. Does this look like a technical drawing of a baseball field? "
            "Answer 'yes' or 'no' and explain."
        )
        vlm_res = query_vlm(vlm_prompt, final_img)
        
        if vlm_res.get("success") and "yes" in vlm_res.get("parsed", {}).get("answer", "").lower():
            score += 30
            feedback.append("Visual verification passed.")
        else:
            feedback.append("Visual verification failed or uncertain.")
    else:
        feedback.append("No screenshot available for visual check.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }