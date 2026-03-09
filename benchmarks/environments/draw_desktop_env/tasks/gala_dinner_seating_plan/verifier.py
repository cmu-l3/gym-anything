#!/usr/bin/env python3
"""
Verifier for Gala Dinner Seating Plan task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gala_dinner_seating_plan(traj, env_info, task_info):
    """
    Verifies the gala dinner seating plan task.
    
    Criteria:
    1. File Creation (10 pts)
    2. PNG Export (10 pts)
    3. Room Elements (Stage, Bar) (15 pts)
    4. Guest Tables (Count ~6) (20 pts)
    5. Chair Count (Approx 48-54) (20 pts)
    6. VIP Styling (Gold/Yellow on 2 tables) (10 pts)
    7. VLM Verification (Visual confirmation of layout) (15 pts)
    """
    
    # 1. Retrieve Result Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)

    analysis = data.get('analysis', {})
    
    score = 0
    feedback = []

    # --- Programmatic Checks (85 points) ---

    # 1. File Creation & Modification (10 pts)
    if data.get('file_exists') and data.get('file_modified'):
        score += 10
        feedback.append("Draw.io file created and saved.")
    elif data.get('file_exists'):
        score += 5
        feedback.append("Draw.io file exists but timestamp is old.")
    else:
        feedback.append("Draw.io file not found.")

    # 2. PNG Export (10 pts)
    if data.get('png_exists') and data.get('png_size', 0) > 1000:
        score += 10
        feedback.append("PNG export found.")
    else:
        feedback.append("PNG export missing or empty.")

    # 3. Room Elements (Stage/Bar) (15 pts)
    elements_found = 0
    if analysis.get('has_stage'):
        elements_found += 1
        feedback.append("Stage labeled.")
    if analysis.get('has_bar'):
        elements_found += 1
        feedback.append("Bar labeled.")
    
    score += min(15, elements_found * 7.5)
    
    # 4. Guest Table Count (20 pts)
    # Expecting 6 round tables. Allow small margin for different drawing methods.
    # Note: If user grouped table+chairs, XML parsing might see groups instead of individual shapes.
    # We rely heavily on VLM for layout if XML is ambiguous, but XML gives base confidence.
    round_tables = analysis.get('round_table_count', 0)
    if 5 <= round_tables <= 7:
        score += 20
        feedback.append(f"Correct number of round tables ({round_tables}).")
    elif round_tables > 0:
        score += 10
        feedback.append(f"Incorrect number of round tables found: {round_tables} (Expected 6).")
    else:
        feedback.append("No round tables detected in XML.")

    # 5. Chair Count (20 pts)
    # Total guests 54. Expecting ~48-60 small shapes.
    chairs = analysis.get('chair_count', 0)
    if chairs >= 40:
        score += 20
        feedback.append(f"Chair count sufficient ({chairs}).")
    elif chairs >= 10:
        score += 10
        feedback.append(f"Chair count low ({chairs}). Expected ~50.")
    else:
        feedback.append("Few or no chairs detected via XML analysis.")

    # 6. VIP Styling (10 pts)
    vip_count = analysis.get('vip_highlight_count', 0)
    if vip_count >= 2:
        score += 10
        feedback.append("VIP tables highlighted.")
    elif vip_count == 1:
        score += 5
        feedback.append("One VIP table highlighted.")
    else:
        feedback.append("No VIP highlighting detected (Gold/Yellow fill).")


    # --- VLM Verification (15 points) ---
    # Used to verify the spatial grid layout which is hard to check via XML list
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        Review this floor plan diagram for a gala dinner.
        Check for:
        1. A rectangular stage at the top.
        2. A layout of 6 round tables arranged in 2 rows.
        3. A rectangular head table facing the stage.
        4. Tables numbered 1 and 2 colored yellow/gold.
        
        Answer JSON: {"layout_correct": bool, "vip_colored": bool, "stage_visible": bool}
        """
        try:
            vlm_res = query_vlm(
                images=[final_screenshot],
                prompt=prompt,
                return_json=True
            )
            
            if vlm_res.get('stage_visible'): vlm_score += 5
            if vlm_res.get('layout_correct'): vlm_score += 5
            if vlm_res.get('vip_colored') and vip_count == 0: # Bonus if XML missed it
                vlm_score += 5
                feedback.append("VLM confirmed VIP colors.")
            elif vlm_res.get('vip_colored'):
                vlm_score += 5
            
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback points if XML was strong
            if score > 60: vlm_score = 15

    score += vlm_score
    feedback.append(f"VLM visual check score: {vlm_score}/15")

    # Final Pass Determination
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }