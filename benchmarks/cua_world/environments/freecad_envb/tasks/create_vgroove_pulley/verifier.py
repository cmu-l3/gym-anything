#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vgroove_pulley(traj, env_info, task_info):
    """
    Verifies the creation of a V-groove pulley.
    
    Scoring Criteria:
    1. FCStd file creation (10 pts)
    2. STEP file export (10 pts)
    3. Valid solid geometry (10 pts)
    4. Correct Bounding Box (20 pts)
    5. Correct Volume (indicates groove presence) (20 pts)
    6. Center Bore presence (10 pts)
    7. Visual VLM verification (20 pts)
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
    
    # 1. File checks
    if result.get("fcstd_exists") and result.get("fcstd_valid_time"):
        score += 10
        feedback.append("FCStd file created.")
    else:
        feedback.append("FCStd file missing or old.")

    if result.get("step_exists") and result.get("step_valid_time") and result.get("step_size", 0) > 1000:
        score += 10
        feedback.append("STEP file exported.")
    else:
        feedback.append("STEP file missing or invalid.")

    # 2. Geometric Analysis
    analysis = result.get("analysis", {})
    if analysis.get("error"):
        feedback.append(f"Geometry analysis failed: {analysis['error']}")
    
    if analysis.get("valid_solid"):
        score += 10
        feedback.append("Valid 3D solid found.")
        
        # Bounding Box (Target: 60x60x15)
        # The list is sorted in export_result.sh, so we expect [15, 60, 60] approx
        bbox = analysis.get("bbox", [0,0,0])
        # Allow some tolerance (e.g., if rotation isn't perfectly aligned, but sorted helps)
        # Expected: Smallest dim ~15, Largest two ~60
        if (14 <= bbox[0] <= 16) and (59 <= bbox[1] <= 61) and (59 <= bbox[2] <= 61):
            score += 20
            feedback.append("Dimensions correct (60x15mm).")
        else:
            feedback.append(f"Dimensions incorrect: {bbox}")

        # Volume Check (Target ~39169 mm3)
        # Range 38000 - 41000 is safe
        vol = analysis.get("volume", 0)
        if 38000 <= vol <= 41500:
            score += 20
            feedback.append("Volume correct (indicates V-groove).")
        else:
            feedback.append(f"Volume mismatch ({vol:.0f} mm3).")

        # Bore Check
        if analysis.get("has_bore"):
            score += 10
            feedback.append("Center bore detected.")
        else:
            feedback.append("Center bore not detected.")
    else:
        feedback.append("No valid solid to analyze.")

    # 3. VLM Verification
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    if final_screenshot:
        prompt = """
        You are verifying a FreeCAD task. The user should have modeled a V-groove pulley wheel.
        Look for:
        1. A cylindrical wheel shape.
        2. A V-shaped groove around the outer edge.
        3. A hole in the center.
        4. The object should look like a mechanical pulley.
        
        Is this object visible?
        """
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        if vlm_res.get("success"):
            # Simple heuristic: if positive response
            content = vlm_res.get("content", "").lower()
            if "yes" in content and "pulley" in content:
                vlm_score = 20
                feedback.append("Visual verification passed.")
            elif "yes" in content:
                vlm_score = 10
                feedback.append("Visual verification partial.")
            else:
                feedback.append("Visual verification failed.")
    
    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }