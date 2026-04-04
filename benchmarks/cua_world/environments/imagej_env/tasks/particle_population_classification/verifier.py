#!/usr/bin/env python3
"""
Verifier for Particle Population Classification task.

Verification Criteria:
1. Files Exist (10 pts): Both CSVs and the map image exist.
2. Noise Filtering (20 pts): No particles < 60px in either CSV.
3. Small Classification (20 pts): small_particles.csv contains particles 60-350px.
4. Large Classification (20 pts): large_particles.csv contains particles > 350px.
5. Visual Map (30 pts): VLM verifies the map shows blue/green colored particles.

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm: return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM query failed: {e}")
    return None

MAP_EVALUATION_PROMPT = """You are evaluating a scientific image analysis result.
The user was asked to create a "Classification Map" where:
- Small particles are colored BLUE.
- Large particles are colored GREEN.

Look at the provided image (Classification Map).
1. Do you see particles (blob-like shapes)?
2. Do you see TWO distinct colors identifying different particles?
3. Specifically, are there BLUE particles and GREEN particles?
4. Is the background distinct (e.g., black, white, or original gray)?

Respond in JSON:
{
    "visible_particles": true/false,
    "has_two_colors": true/false,
    "has_blue_particles": true/false,
    "has_green_particles": true/false,
    "confidence": "high/medium/low"
}
"""

def verify_particle_classification(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load programmatic results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/particle_classification_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name): os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Criterion 1: Files Exist (10 pts) ---
    small_exists = result["small_csv"]["exists"] and result["small_csv"]["created_during_task"]
    large_exists = result["large_csv"]["exists"] and result["large_csv"]["created_during_task"]
    map_exists = result["map_image"]["exists"] and result["map_image"]["created_during_task"]

    if small_exists and large_exists:
        score += 5
        feedback.append("CSV files created.")
    else:
        feedback.append("Missing one or both CSV files.")

    if map_exists:
        score += 5
        feedback.append("Classification map created.")
    else:
        feedback.append("Missing classification map.")

    # --- Criterion 2: Noise Filtering (20 pts) ---
    # Fail if min_area < 60 in either file
    small_min = result["small_csv"].get("min_area", 0)
    large_min = result["large_csv"].get("min_area", 0)
    
    if small_exists and large_exists:
        if small_min >= 59.5 and large_min >= 59.5: # 0.5 tolerance
            score += 20
            feedback.append("Noise filtering successful (no particles < 60px).")
        else:
            feedback.append(f"Noise filtering failed. Found particles < 60px (Small min: {small_min}, Large min: {large_min}).")

    # --- Criterion 3: Small Classification (20 pts) ---
    # Small: 60 <= Area <= 350
    small_max = result["small_csv"].get("max_area", 0)
    small_count = result["small_csv"].get("count", 0)
    
    if small_exists:
        if small_count > 0:
            if small_max <= 355: # Tolerance
                score += 20
                feedback.append(f"Small population correctly classified (Max area: {small_max}).")
            else:
                score += 5 # Partial credit for creating file
                feedback.append(f"Small population contains large particles (Max: {small_max} > 350).")
        else:
            feedback.append("Small particles file is empty.")

    # --- Criterion 4: Large Classification (20 pts) ---
    # Large: Area > 350
    large_min_val = result["large_csv"].get("min_area", 0)
    large_count = result["large_csv"].get("count", 0)

    if large_exists:
        if large_count > 0:
            if large_min_val >= 345: # Tolerance
                score += 20
                feedback.append(f"Large population correctly classified (Min area: {large_min_val}).")
            else:
                score += 5
                feedback.append(f"Large population contains small particles (Min: {large_min_val} < 350).")
        else:
            feedback.append("Large particles file is empty.")

    # --- Criterion 5: Visual Map VLM Check (30 pts) ---
    if map_exists and query_vlm:
        # Retrieve the map image to check
        # Since we can't easily download the image bytes here without 'get_file_content' (which isn't in env_info usually),
        # we will rely on the *Final Screenshot* or Trajectory if the map file isn't viewable.
        # However, standard practice here is to look at the final screenshot which likely shows the map open in Fiji.
        
        final_screenshot = get_final_screenshot(traj)
        
        vlm_res = _vlm_query(query_vlm, MAP_EVALUATION_PROMPT, image=final_screenshot)
        
        if vlm_res:
            if vlm_res.get("has_blue_particles") and vlm_res.get("has_green_particles"):
                score += 30
                feedback.append("VLM confirms map shows Blue and Green particles.")
            elif vlm_res.get("has_two_colors"):
                score += 20
                feedback.append("VLM sees two colors, but maybe not specifically Blue/Green (Partial credit).")
            else:
                feedback.append("VLM did not detect distinct colored particles in the final view.")
        else:
            feedback.append("VLM query failed or inconclusive.")
    elif map_exists:
        # Fallback if no VLM but file exists (trusting file existence slightly)
        score += 10
        feedback.append("Map file exists (VLM unavailable).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }