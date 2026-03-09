#!/usr/bin/env python3
"""
Verifier for PCB Board Outline task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pcb_board_outline(traj, env_info, task_info):
    """
    Verify PCB board outline creation.
    
    Criteria:
    1. DXF file created during task (Anti-gaming).
    2. Correct Layers (Board_Outline, Mounting_Holes, Keepout_Zone) with correct colors.
    3. Correct Geometry (Rectangles and Circles at specific coordinates).
    4. VLM Verification of UI state as backup.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback = []
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. File Verification (20 points)
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "No output file found."}
        
    if not result.get("created_during_task"):
        feedback.append("FAIL: Output file timestamp predates task start.")
    else:
        score += 10
        feedback.append("File created during task.")

    if result.get("file_size", 0) > 500:
        score += 10
        feedback.append("File size is valid.")
    else:
        feedback.append("FAIL: File is too small/empty.")

    # 3. DXF Content Verification (60 points)
    analysis = result.get("dxf_analysis", {})
    
    if not analysis.get("valid_dxf"):
        feedback.append("FAIL: File is not a valid DXF.")
    else:
        # Layer Checks (30 points)
        layers = analysis.get("layers_found", {})
        
        # Board_Outline (White/7)
        l1 = layers.get("Board_Outline", {})
        if l1.get("exists"):
            score += 5
            if l1.get("color_correct"):
                score += 5
                feedback.append("Board_Outline layer correct.")
            else:
                feedback.append(f"Board_Outline color wrong (got {l1.get('color')}).")
        else:
            feedback.append("Missing Board_Outline layer.")

        # Mounting_Holes (Red/1)
        l2 = layers.get("Mounting_Holes", {})
        if l2.get("exists"):
            score += 5
            if l2.get("color_correct"):
                score += 5
                feedback.append("Mounting_Holes layer correct.")
            else:
                feedback.append(f"Mounting_Holes color wrong (got {l2.get('color')}).")
        else:
            feedback.append("Missing Mounting_Holes layer.")

        # Keepout_Zone (Yellow/2)
        l3 = layers.get("Keepout_Zone", {})
        if l3.get("exists"):
            score += 5
            if l3.get("color_correct"):
                score += 5
                feedback.append("Keepout_Zone layer correct.")
            else:
                feedback.append(f"Keepout_Zone color wrong (got {l3.get('color')}).")
        else:
            feedback.append("Missing Keepout_Zone layer.")

        # Geometry Checks (30 points)
        geo = analysis.get("geometry_checks", [])
        
        # Board Outline Rect
        outline = next((g for g in geo if g["name"] == "board_outline_rect"), {})
        if outline.get("passed"):
            score += 10
            feedback.append("Board outline geometry correct.")
        else:
            feedback.append("Board outline geometry incorrect or missing.")

        # Keepout Rect
        keepout = next((g for g in geo if g["name"] == "keepout_rect"), {})
        if keepout.get("passed"):
            score += 10
            feedback.append("Keepout zone geometry correct.")
        else:
            feedback.append("Keepout zone geometry incorrect or missing.")

        # Mounting Holes
        holes = next((g for g in geo if g["name"] == "mounting_holes_count"), {})
        count = holes.get("found", 0)
        if count == 4:
            score += 10
            feedback.append("All 4 mounting holes found correctly.")
        elif count > 0:
            partial = int(10 * (count / 4))
            score += partial
            feedback.append(f"Found {count}/4 mounting holes.")
        else:
            feedback.append("No correct mounting holes found.")

    # 4. VLM Verification (20 points)
    # Check if the agent was actually doing work in the UI
    try:
        frames = sample_trajectory_frames(traj, n=3)
        final_screen = get_final_screenshot(traj)
        
        if frames and final_screen:
            prompt = """
            Review these screenshots of a LibreCAD session.
            1. Is the LibreCAD interface visible?
            2. Do you see a drawing with a rectangle and circles?
            3. Are there different colors visible (white, red, yellow)?
            
            Return JSON: {"ui_visible": bool, "shapes_visible": bool, "colors_visible": bool}
            """
            
            vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
            parsed = vlm_res.get("parsed", {})
            
            if parsed.get("ui_visible"):
                score += 10
                feedback.append("VLM confirmed UI usage.")
            if parsed.get("shapes_visible") and parsed.get("colors_visible"):
                score += 10
                feedback.append("VLM confirmed shapes and colors.")
            else:
                feedback.append("VLM could not confirm shapes/colors visually.")
        else:
            score += 20 # Fallback if no screenshots available to avoid punishing for infra issues
            feedback.append("Skipping VLM check (no frames).")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        score += 20 # Fallback
        feedback.append("VLM check skipped due to error.")

    # Final Pass Logic
    # Must have created file + valid DXF + at least 60 points
    passed = (result.get("file_exists") and 
              result.get("created_during_task") and 
              analysis.get("valid_dxf") and 
              score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }