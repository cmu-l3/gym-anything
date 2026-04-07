#!/usr/bin/env python3
"""
Verifier for Multi-Wavelength ROI Transfer and Excitation Measurement task.

Scoring (100 points total):
  Criterion 1: CSV Exported with 2 rows (10 pts)
  Criterion 2: Exact ROI Transfer (Area matches identically) (40 pts)
  Criterion 3: Sufficient Region Size (Area >= 20000) (15 pts)
  Criterion 4: Accurate Ratio Calculation (15 pts)
  Criterion 5: Visual Semantic Accuracy via VLM (20 pts)

Pass threshold: 70 points AND Exact ROI Transfer must be verified.
"""

import json
import tempfile
import os
import logging
import math

logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, image=None, images=None):
    """Run VLM query with single or multiple images. Returns parsed dict or None."""
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

def verify_eagle_roi_transfer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
        
    score = 0
    feedback = []
    
    # 1. Read JSON results from the container
    result = {}
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)
            
    # 2. Programmatic Checks
    
    # Criterion 1: CSV Exported
    if result.get("csv_exists") and result.get("num_rows", 0) >= 2:
        score += 10
        feedback.append("CSV exported with at least 2 rows.")
    else:
        feedback.append("CSV export missing or insufficient rows.")
        
    row1 = result.get("row1", {})
    row2 = result.get("row2", {})
    
    # Utility to find data irrespective of AstroImageJ's exact header casing
    def get_val(row, possible_keys):
        for k in row.keys():
            if k and any(pk.lower() in k.lower() for pk in possible_keys):
                try:
                    return float(row[k])
                except ValueError:
                    continue
        return None
        
    area1 = get_val(row1, ['area'])
    area2 = get_val(row2, ['area'])
    intden1 = get_val(row1, ['intden', 'integrated density', 'rawintden'])
    intden2 = get_val(row2, ['intden', 'integrated density', 'rawintden'])
    
    # Criterion 2: Exact ROI Transfer (Core constraint)
    exact_match = False
    if area1 is not None and area2 is not None:
        if area1 == area2:
            exact_match = True
            score += 40
            feedback.append(f"Exact ROI transfer confirmed (Area1={area1}, Area2={area2}).")
        else:
            feedback.append(f"Areas do not match exactly (Area1={area1}, Area2={area2}). ROI was likely redrawn manually.")
    else:
        feedback.append("Could not find 'Area' column in CSV or area values missing.")
        
    # Criterion 3: Sufficient Region Size
    if area1 is not None:
        if area1 >= 20000:
            score += 15
            feedback.append(f"Region size sufficient (Area={area1} >= 20000).")
        else:
            feedback.append(f"Region size too small (Area={area1} < 20000). Did you select the whole pillar structure?")
            
    # Criterion 4: Accurate Ratio Calculation
    if result.get("txt_exists") and result.get("reported_ratio") is not None:
        reported_ratio = result.get("reported_ratio")
        if intden1 and intden2 and intden2 != 0:
            expected_ratio1 = intden1 / intden2
            expected_ratio2 = intden2 / intden1 # In case they did [OIII]/H-alpha by mistake
            
            if math.isclose(reported_ratio, expected_ratio1, rel_tol=0.05):
                score += 15
                feedback.append(f"Excitation ratio calculation accurate ({reported_ratio}).")
            elif math.isclose(reported_ratio, expected_ratio2, rel_tol=0.05):
                score += 15
                feedback.append(f"Excitation ratio calculation accurate (inverted but acceptable, {reported_ratio}).")
            else:
                feedback.append(f"Excitation ratio calculation incorrect (reported: {reported_ratio}, expected approx: {expected_ratio1}).")
        else:
            feedback.append(f"Reported ratio found ({reported_ratio}), but could not calculate expected ratio from CSV IntDen.")
    else:
        feedback.append("Excitation ratio text file missing or could not parse number.")
        
    # Criterion 5: Visual Semantic Accuracy via VLM
    query_vlm = env_info.get('query_vlm')
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        if final and frames:
            prompt = '''You are analyzing screenshots from an agent performing a task in AstroImageJ.
The task involves drawing a polygonal ROI (Region of Interest) around the central "Pillars of Creation" in the Eagle Nebula.

Look at the trajectory frames and final screenshot.
1. Is there evidence that the user used the Polygon Selection Tool to draw an irregular shape? (You should see a yellow or colored polygon outline).
2. Is the polygon drawn roughly around the central pillar structures of the nebula (the dark vertical dust columns in the center)?

Respond in JSON format:
{
    "polygon_visible": true/false,
    "drawn_around_pillars": true/false
}
'''
            vlm_resp = _vlm_query(query_vlm, prompt, images=frames + [final])
            if vlm_resp:
                if vlm_resp.get("polygon_visible") and vlm_resp.get("drawn_around_pillars"):
                    score += 20
                    feedback.append("VLM confirmed polygon drawn around the pillars.")
                else:
                    feedback.append("VLM did not confirm polygon drawn around the pillars.")
            else:
                feedback.append("VLM query failed.")
        else:
            feedback.append("No trajectory frames available for VLM verification.")
    except Exception as e:
        feedback.append(f"VLM process failed: {str(e)}")
        
    # To pass, they must achieve the exact area match and have a total score >= 70
    passed = (score >= 70) and exact_match
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }