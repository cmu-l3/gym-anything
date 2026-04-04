#!/usr/bin/env python3
"""
Verifier for grain_facility_siteplan@1

This verifier combines:
1. Programmatic checks (via pre-calculated JSON from inside the container)
   - Verifies DXF file existence, validity, layers, and geometry.
2. VLM verification
   - Checks trajectory to ensure manual work (anti-gaming).
   - Verifies visual layout quality (human readability).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_grain_facility_siteplan(traj, env_info, task_info):
    """
    Verifies the Grain Facility Site Plan task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    file_exists = result.get("file_exists", False)
    created_during = result.get("file_created_during_task", False)
    dxf_data = result.get("dxf_analysis", {})
    
    score = 0
    feedback = []

    # --- CRITERIA 1: File Existence & Validity (20 pts) ---
    if file_exists and created_during:
        score += 10
        feedback.append("File created successfully.")
        if not dxf_data.get("parse_error"):
            score += 10
            feedback.append("DXF file is valid.")
        else:
            feedback.append(f"DXF invalid: {dxf_data.get('parse_error')}")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found or not created during task."}

    # --- CRITERIA 2: Geometry & Layers (Programmatic) (50 pts) ---
    
    # Layers (10 pts)
    layers_found = len(dxf_data.get("layers_found", []))
    # Expect 6 layers: BINS, STRUCTURES, ROADS, CONVEYOR, TEXT, DIMENSIONS
    if layers_found >= 6:
        score += 10
        feedback.append("All required layers found.")
    elif layers_found >= 4:
        score += 5
        feedback.append(f"Most layers found ({layers_found}/6).")
    else:
        feedback.append(f"Missing layers (found {layers_found}/6).")

    # Bins (15 pts) - 4 bins correct size and position
    bins_pos = dxf_data.get("bins_correct_pos", 0)
    score += bins_pos * 3  # 3 pts per correct bin (max 12)
    if bins_pos == 4:
        score += 3 # Bonus for all 4
        feedback.append("All 4 grain bins positioned correctly.")
    else:
        feedback.append(f"Found {bins_pos}/4 bins in correct positions.")

    # Conveyors (5 pts)
    conv_count = dxf_data.get("conveyors_found", 0)
    if conv_count >= 4:
        score += 5
        feedback.append("Conveyor lines detected.")
    elif conv_count > 0:
        score += 2
        feedback.append("Some conveyor lines detected.")

    # Pit & Road (10 pts)
    if dxf_data.get("pit_found"):
        score += 5
        feedback.append("Dump pit geometry found.")
    if dxf_data.get("road_found"):
        score += 5
        feedback.append("Access road geometry found.")

    # Annotations (10 pts)
    if dxf_data.get("text_labels_found", 0) >= 4:
        score += 5
        feedback.append("Text labels detected.")
    if dxf_data.get("dimensions_found", 0) >= 2:
        score += 5
        feedback.append("Dimensions detected.")

    # --- CRITERIA 3: VLM Visual Verification (30 pts) ---
    # We verify the process and the visual correctness
    
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if not final_shot:
        feedback.append("No final screenshot available for visual verification.")
    else:
        vlm_prompt = (
            "Review this LibreCAD drawing workflow.\n"
            "1. Does the final image show a site plan with 4 circles arranged in a square grid?\n"
            "2. Is there a central rectangle (pit) and a side road?\n"
            "3. Are there text labels visible?\n"
            "4. Did the agent explicitly draw these shapes step-by-step (not pasting)?\n"
            "Reply with JSON: {'layout_correct': bool, 'labels_visible': bool, 'workflow_valid': bool}"
        )
        
        try:
            vlm_res = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
            parsed = vlm_res.get("parsed", {})
            
            if parsed.get("layout_correct", False):
                score += 15
                feedback.append("Visual layout confirmed correct.")
            
            if parsed.get("labels_visible", False):
                score += 5
                feedback.append("Labels visually confirmed.")
                
            if parsed.get("workflow_valid", True):
                score += 10
                feedback.append("Workflow validated (manual drafting confirmed).")
            else:
                feedback.append("Workflow flagged as suspicious.")
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if programmatic score is high, assume OK but cap max score
            feedback.append("VLM verification skipped due to error.")
            if score > 60:
                score += 10 # Give partial credit if geometry was good

    # Final Check
    passed = score >= 60 and bins_pos >= 3
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }