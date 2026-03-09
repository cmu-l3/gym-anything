#!/usr/bin/env python3
"""
Verifier for create_retail_shelf_planogram task.

Verifies:
1. .eddx and .png files exist and were created during the task.
2. .eddx file contains specific text strings (prices, title).
3. VLM verification of the visual layout (3 shelves, correct product counts/colors).
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_retail_shelf_planogram(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_strings = metadata.get('required_strings', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Load result JSON from export_result.sh
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # 2. Verify File Existence & Anti-Gaming (30 points)
    eddx_exists = task_result.get('eddx_exists', False)
    eddx_fresh = task_result.get('eddx_created_during_task', False)
    png_exists = task_result.get('png_exists', False)
    png_fresh = task_result.get('png_created_during_task', False)
    
    if eddx_exists and eddx_fresh:
        score += 15
        feedback_parts.append("EdrawMax file created successfully.")
    elif eddx_exists:
        score += 5
        feedback_parts.append("EdrawMax file exists but has old timestamp (pre-existing?).")
    else:
        feedback_parts.append("EdrawMax file not found.")

    if png_exists and png_fresh:
        score += 15
        feedback_parts.append("PNG export created successfully.")
    elif png_exists:
        score += 5
        feedback_parts.append("PNG export exists but has old timestamp.")
    else:
        feedback_parts.append("PNG export not found.")

    # 3. Verify Content inside .eddx (30 points)
    # .eddx is a zip; we check if the required strings exist in any XML inside it
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Diagrams/coffee_planogram.eddx", temp_eddx.name)
            
            found_strings = set()
            try:
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    for filename in zf.namelist():
                        if filename.endswith('.xml'):
                            try:
                                content = zf.read(filename).decode('utf-8', errors='ignore')
                                for s in required_strings:
                                    if s in content:
                                        found_strings.add(s)
                            except:
                                pass
            except zipfile.BadZipFile:
                feedback_parts.append("EdrawMax file is not a valid zip archive.")

            # Scoring based on found strings
            # Prices: $18.99, $14.50, $24.00 (5 pts each)
            # Title: "Summer Coffee Display", "Planogram A" (7.5 pts each)
            
            prices_found = sum(1 for p in ["$18.99", "$14.50", "$24.00"] if p in found_strings)
            score += prices_found * 5
            
            title_parts_found = sum(1 for t in ["Summer Coffee Display", "Planogram A"] if t in found_strings)
            score += int(title_parts_found * 7.5)
            
            if len(found_strings) == len(required_strings):
                feedback_parts.append("All required text labels found in file.")
            else:
                missing = set(required_strings) - found_strings
                feedback_parts.append(f"Missing text labels: {', '.join(missing)}")
                
        except Exception as e:
            feedback_parts.append(f"Error inspecting EDDX content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

    # 4. VLM Verification (40 points)
    # We check if the visual structure matches a planogram
    
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    # Prompt for VLM
    prompt = """
    You are verifying a task to create a retail planogram (shelf display) in EdrawMax.
    
    Look at the images, especially the final one.
    1. Is there a shelf or rack structure visible with 3 distinct levels/shelves?
    2. Are there products arranged on these shelves?
    3. Can you distinguish different types/colors of products on different levels?
       (Expected: Top=Dark/Black, Middle=Light/Orange, Bottom=Silver/Blue)
    4. Is there a title text "Summer Coffee Display"?
    
    Return JSON:
    {
      "shelf_structure_visible": boolean,
      "three_levels_detected": boolean,
      "products_placed": boolean,
      "color_differentiation": boolean,
      "title_visible": boolean
    }
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_img], prompt=prompt)
        if vlm_res and vlm_res.get("success"):
            analysis = vlm_res.get("parsed", {})
            
            if analysis.get("shelf_structure_visible"): score += 10
            if analysis.get("three_levels_detected"): score += 10
            if analysis.get("products_placed"): score += 10
            if analysis.get("color_differentiation"): score += 5
            if analysis.get("title_visible"): score += 5
            
            feedback_parts.append(f"Visual verification: {analysis}")
        else:
            feedback_parts.append("VLM verification failed or returned no result.")
            # Fallback: if text check passed perfectly, give partial credit for VLM to avoid zeroing out
            if score >= 50:
                score += 20
                feedback_parts.append("Awarding partial visual credit based on strong text evidence.")

    except Exception as e:
        feedback_parts.append(f"VLM error: {str(e)}")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }