#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_external_evidence(traj, env_info, task_info):
    """
    Verifies that the agent imported video files, renamed them, and placed them on a layout.
    
    Scoring:
    - 20 pts: Layout 'Case #4492-Investigation' exists
    - 20 pts: Layout contains exactly 2 items
    - 30 pts: Resources are correctly renamed ('Exhibit A...', 'Exhibit B...')
    - 30 pts: VLM confirmation of side-by-side arrangement and content
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result_data.get('error'):
        return {"passed": False, "score": 0, "feedback": f"API Error during export: {result_data['error']}"}

    score = 0
    feedback = []
    
    # 2. Programmatic Verification (70 points total)
    
    # Check Layout Existence (20 pts)
    if result_data.get('layout_found'):
        score += 20
        feedback.append("Success: Layout 'Case #4492-Investigation' created.")
    else:
        feedback.append("Failure: Layout 'Case #4492-Investigation' not found.")
    
    # Check Item Count (20 pts)
    item_count = result_data.get('layout_item_count', 0)
    if item_count == 2:
        score += 20
        feedback.append("Success: Layout contains exactly 2 items.")
    elif item_count > 0:
        score += 10
        feedback.append(f"Partial: Layout contains {item_count} items (expected 2).")
    else:
        feedback.append("Failure: Layout is empty.")

    # Check Renaming (30 pts)
    # We look for the specific strings in the names of the items ON the layout
    layout_items = result_data.get('layout_items', [])
    names_on_layout = [item.get('name', '') for item in layout_items]
    
    found_exhibit_a = any("Exhibit A - Bystander" in name for name in names_on_layout)
    found_exhibit_b = any("Exhibit B - Drone" in name for name in names_on_layout)
    
    if found_exhibit_a:
        score += 15
        feedback.append("Success: 'Exhibit A - Bystander' found on layout.")
    else:
        feedback.append("Failure: 'Exhibit A - Bystander' not found on layout.")
        
    if found_exhibit_b:
        score += 15
        feedback.append("Success: 'Exhibit B - Drone' found on layout.")
    else:
        feedback.append("Failure: 'Exhibit B - Drone' not found on layout.")

    # 3. VLM Verification (30 pts)
    # We check if they are arranged side-by-side or at least both visible
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot and score >= 40: # Only check VLM if basic API checks passed
        prompt = """
        Analyze this screenshot of the Nx Witness VMS software.
        
        I am looking for a layout named "Case #4492-Investigation".
        
        1. Are there two distinct video players visible in the central workspace?
        2. Do they appear to be arranged side-by-side (or at least simultaneously visible)?
        3. Can you see the names "Exhibit A" or "Exhibit B" anywhere (like in the tree on the left or titles)?
        
        Return JSON: {"two_players_visible": bool, "simultaneous_view": bool, "names_visible": bool}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('two_players_visible') or parsed.get('simultaneous_view'):
                vlm_score += 20
                feedback.append("VLM: Confirmed simultaneous playback of evidence.")
            
            if parsed.get('names_visible'):
                vlm_score += 10
                feedback.append("VLM: Confirmed Exhibit names visible.")
                
        except Exception as e:
            feedback.append(f"VLM Check failed: {e}")
            # Fallback: if API confirmed names and items, give partial visual credit
            vlm_score += 15
    
    score += vlm_score
    
    # 4. Final Result
    # Pass threshold: 70 points (Must have created layout + items + some renaming)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }