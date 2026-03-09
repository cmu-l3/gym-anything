#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_film_set_lighting_plot(traj, env_info, task_info):
    """
    Verifies the Film Set Lighting Plot task.
    
    Scoring Breakdown (100 pts):
    - 20 pts: File Existence & Freshness (Anti-gaming)
    - 30 pts: Content Analysis (Keywords found in diagram)
    - 20 pts: Shape Count & Structure
    - 30 pts: VLM Verification (Visual check of layout/legend)
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/final_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. File Verification (20 pts)
    if result.get("drawio_exists") and result.get("drawio_fresh"):
        score += 10
        feedback.append("Drawio file created successfully.")
    else:
        feedback.append("Drawio file missing or not new.")

    if result.get("pdf_exists") and result.get("pdf_fresh"):
        score += 10
        feedback.append("PDF export created successfully.")
    else:
        feedback.append("PDF export missing.")

    # 3. Content Analysis (30 pts)
    keywords_found = result.get("keywords_found", [])
    required_keywords = ["l1", "l2", "l3", "l4", "l5"] # The specific light IDs
    
    lights_found = sum(1 for k in required_keywords if k in keywords_found)
    if lights_found >= 5:
        score += 20
        feedback.append(f"All 5 light IDs found ({lights_found}/5).")
    elif lights_found > 0:
        score += int((lights_found / 5) * 20)
        feedback.append(f"Found some light IDs ({lights_found}/5).")
    else:
        feedback.append("No light IDs (L1-L5) found in diagram text.")

    # Check for context keywords
    context_keywords = ["detective", "suspect", "skypanel", "fresnel", "source 4"]
    context_found = sum(1 for k in context_keywords if k in keywords_found)
    if context_found >= 3:
        score += 10
        feedback.append("Context keywords (actors/fixtures) found.")

    # 4. Shape & Structure (20 pts)
    shape_count = result.get("shape_count", 0)
    if shape_count >= 10:
        score += 10
        feedback.append(f"Sufficient shapes count ({shape_count}).")
    else:
        feedback.append(f"Shape count too low ({shape_count}), expected >10.")

    if result.get("has_legend"):
        score += 10
        feedback.append("Legend text detected.")
    else:
        feedback.append("Legend not detected in text.")

    # 5. VLM Verification (30 pts)
    # We use VLM to verify the visual layout which is hard to check programmatically
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = """
        Analyze this film lighting plot diagram.
        1. Is there a room outline with a window and door?
        2. Are there shapes representing actors in the center?
        3. Is there a 'Legend' section defining symbols?
        4. Are there approximately 5 distinct lighting fixtures arranged around the center?
        
        Answer JSON: {"room_visible": bool, "actors_visible": bool, "legend_visible": bool, "lights_visible": bool}
        """
        
        vlm_res = query_vlm(image=final_screenshot, prompt=prompt)
        
        if vlm_res and isinstance(vlm_res, dict):
            # Parse the string response if it's not already a dict
            # (Assuming query_vlm handles JSON extraction, otherwise we'd need parsing logic here)
            # For robustness, we check the 'parsed' field if standard gym_anything VLM wrapper
            if "parsed" in vlm_res:
                vlm_data = vlm_res["parsed"]
            else:
                vlm_data = vlm_res # fallback
            
            vlm_score = 0
            if vlm_data.get("room_visible"): vlm_score += 5
            if vlm_data.get("actors_visible"): vlm_score += 5
            if vlm_data.get("legend_visible"): vlm_score += 10
            if vlm_data.get("lights_visible"): vlm_score += 10
            
            score += vlm_score
            feedback.append(f"Visual verification score: {vlm_score}/30")
        else:
            # Fallback if VLM fails: give partial credit if PDF exists (implies visual work)
            if result.get("pdf_exists"):
                score += 15
                feedback.append("VLM failed, granting partial credit for PDF existence.")
    else:
        feedback.append("No screenshot available for visual verification.")

    # Final tally
    passed = score >= 60 and result.get("drawio_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }