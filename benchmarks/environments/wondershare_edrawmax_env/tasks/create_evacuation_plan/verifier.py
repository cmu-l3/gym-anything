#!/usr/bin/env python3
"""
Verifier for create_evacuation_plan task.
Checks for valid EDDX/PNG files and specific diagram content (walls, symbols, text).
"""
import os
import json
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_evacuation_plan(traj, env_info, task_info):
    """
    Verify the evacuation plan creation.
    
    Criteria:
    1. Files (.eddx and .png) exist and were created during the task.
    2. EDDX file is a valid ZIP and contains specific XML keywords:
       - Structure: "Wall", "Door"
       - Symbols: "Extinguisher", "Exit"
       - Text: "Server Room", "Evacuation Plan"
       - Route: "Arrow" or "Connector"
    3. VLM verification of the PNG output to confirm visual correctness.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata from export_result.sh
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Timestamps (20 points) ---
    eddx_exists = result_data.get("eddx_exists", False)
    eddx_created = result_data.get("eddx_created_during_task", False)
    eddx_size = result_data.get("eddx_size", 0)
    
    png_exists = result_data.get("png_exists", False)
    png_created = result_data.get("png_created_during_task", False)
    
    files_ok = False
    if eddx_exists and eddx_created and eddx_size > 5000: # 5KB min for non-empty
        score += 10
        feedback_parts.append("EDDX file created successfully.")
        files_ok = True
    elif eddx_exists:
        feedback_parts.append("EDDX file exists but verification of creation time failed or file too small.")
    else:
        feedback_parts.append("EDDX file not found.")

    if png_exists and png_created and result_data.get("png_size", 0) > 5000:
        score += 10
        feedback_parts.append("PNG export created successfully.")
    elif png_exists:
        feedback_parts.append("PNG file exists but verification of creation time failed.")
    else:
        feedback_parts.append("PNG file not found.")

    # Stop if source file is missing
    if not files_ok:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # --- Criterion 2: EDDX Content Analysis (40 points) ---
    # Download the EDDX file to inspect XML content
    temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
    try:
        copy_from_env("/home/ga/Documents/evacuation_plan.eddx", temp_eddx.name)
        
        xml_content = ""
        is_zip = zipfile.is_zipfile(temp_eddx.name)
        
        if is_zip:
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                # EdrawMax files store page data in XMLs. We read all XMLs.
                for name in zf.namelist():
                    if name.endswith('.xml'):
                        try:
                            xml_content += zf.read(name).decode('utf-8', errors='ignore')
                        except:
                            pass
        
        # Check for keywords in the XML
        # Note: EdrawMax XML often uses "Name" or "Prompt" attributes for shapes
        
        # Structure (Walls/Doors) - 10 pts
        has_walls = "Wall" in xml_content or "Structure" in xml_content
        has_doors = "Door" in xml_content
        if has_walls and has_doors:
            score += 10
            feedback_parts.append("Floor plan structure (walls/doors) detected.")
        else:
            feedback_parts.append(f"Structure missing (Walls: {has_walls}, Doors: {has_doors}).")

        # Safety Symbols - 10 pts
        has_extinguisher = "Extinguisher" in xml_content or "Fire" in xml_content
        has_exit = "Exit" in xml_content or "Emergency" in xml_content
        if has_extinguisher and has_exit:
            score += 10
            feedback_parts.append("Safety symbols (Extinguisher, Exit) detected.")
        elif has_extinguisher or has_exit:
            score += 5
            feedback_parts.append("Some safety symbols detected.")
        else:
            feedback_parts.append("Safety symbols missing.")

        # Text Labels - 10 pts
        has_title = "Evacuation Plan" in xml_content or "Emergency" in xml_content
        has_room = "Server Room" in xml_content
        if has_title and has_room:
            score += 10
            feedback_parts.append("Required text labels detected.")
        else:
            feedback_parts.append("Text labels missing or incorrect.")

        # Route/Arrows - 10 pts
        has_arrows = "Arrow" in xml_content or "Connector" in xml_content or "Direction" in xml_content
        if has_arrows:
            score += 10
            feedback_parts.append("Directional arrows detected.")
        else:
            feedback_parts.append("Evacuation route (arrows) missing.")

    except Exception as e:
        feedback_parts.append(f"Failed to analyze EDDX content: {e}")
    finally:
        if os.path.exists(temp_eddx.name):
            os.unlink(temp_eddx.name)

    # --- Criterion 3: VLM Visual Verification (40 points) ---
    # We check the exported PNG if available, otherwise the final screenshot
    
    image_to_check = None
    if png_exists:
        # Check the exported PNG
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/home/ga/Documents/evacuation_plan.png", temp_png.name)
            image_to_check = temp_png.name
        except:
            pass
    
    if not image_to_check:
        # Fallback to final state screenshot
        image_to_check = get_final_screenshot(traj)

    if image_to_check:
        prompt = """
        Analyze this image of an evacuation plan diagram.
        
        Check for the following visual elements:
        1. Is it a floor plan (top-down view of rooms)?
        2. Are there walls forming at least two distinct rooms?
        3. Is there a red Fire Extinguisher icon?
        4. Is there a green Exit sign icon?
        5. Are there directional arrows showing a path?
        6. Is there a title containing 'Evacuation Plan'?
        
        JSON Response format:
        {
            "is_floor_plan": boolean,
            "has_multiple_rooms": boolean,
            "has_fire_extinguisher": boolean,
            "has_exit_sign": boolean,
            "has_arrows": boolean,
            "has_title": boolean,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_res = query_vlm(prompt=prompt, image=image_to_check)
        
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            vlm_score = 0
            
            if parsed.get("is_floor_plan"): vlm_score += 10
            if parsed.get("has_fire_extinguisher"): vlm_score += 10
            if parsed.get("has_exit_sign"): vlm_score += 10
            if parsed.get("has_arrows"): vlm_score += 10
            
            score += vlm_score
            feedback_parts.append(f"VLM visual verification score: {vlm_score}/40.")
            
            # Bonus consistency check
            if not parsed.get("is_floor_plan") and score > 50:
                score -= 20
                feedback_parts.append("VLM penalty: Image does not look like a floor plan.")
        else:
             feedback_parts.append("VLM verification failed to execute.")
             # Fallback: if XML checks passed high, give partial credit for visual
             if score >= 50:
                 score += 20
                 feedback_parts.append("Granting partial visual points based on XML evidence.")

    # Cleanup temp PNG if created
    if image_to_check and image_to_check != get_final_screenshot(traj) and os.path.exists(image_to_check):
        os.unlink(image_to_check)

    # Final Score Calculation
    passed = score >= 70
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }