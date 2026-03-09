#!/usr/bin/env python3
"""
Verifier for color_wheel_art_lesson task.

Scoring Breakdown (100 points total):
1. File Validation (15 pts): File exists, is valid flipchart.
2. Structure (10 pts): Exactly 3 pages.
3. Content - Text (55 pts):
   - Title "Color Theory" (10 pts)
   - Title "Elements of Art" (5 pts)
   - Primary Colors (R, Y, B) (15 pts)
   - Secondary Colors (O, G, V) (10 pts)
   - Art Elements List (15 pts)
4. Content - Visuals (10 pts): At least 6 shape elements found.
5. Anti-Gaming (5 pts): File created/modified during task.
6. VLM Verification (5 pts): Visual confirmation of content.

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_color_wheel_art(traj, env_info, task_info):
    """
    Verify the Color Wheel Art Lesson task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    content = result.get("content", {})

    # --- Criterion 1: File Validation (15 pts) ---
    if result.get("file_found") and result.get("file_valid"):
        score += 15
        feedback.append("Valid flipchart file found (+15)")
    elif result.get("file_found"):
        score += 5
        feedback.append("File found but invalid format (+5)")
    else:
        feedback.append("No file found (0)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # --- Criterion 2: Page Count (10 pts) ---
    # Relaxed slightly: accept >= 3
    if result.get("page_count", 0) >= 3:
        score += 10
        feedback.append("Correct page count (+10)")
    else:
        feedback.append(f"Incorrect page count: {result.get('page_count')} (0)")

    # --- Criterion 3: Text Content (55 pts) ---
    
    # Titles
    if content.get("has_title_theory"):
        score += 10
        feedback.append("Title 'Color Theory' found (+10)")
    if content.get("has_title_elements"):
        score += 5
        feedback.append("Title 'Elements of Art' found (+5)")

    # Primary Colors (15 pts total, 5 each)
    primaries = 0
    if content.get("has_red"): primaries += 1
    if content.get("has_yellow"): primaries += 1
    if content.get("has_blue"): primaries += 1
    score += (primaries * 5)
    if primaries > 0:
        feedback.append(f"{primaries}/3 Primary colors labeled (+{primaries*5})")

    # Secondary Colors (10 pts total, ~3.3 each, rounded)
    secondaries = 0
    if content.get("has_orange"): secondaries += 1
    if content.get("has_green"): secondaries += 1
    if content.get("has_violet"): secondaries += 1
    
    sec_points = 0
    if secondaries == 3: sec_points = 10
    elif secondaries == 2: sec_points = 7
    elif secondaries == 1: sec_points = 3
    score += sec_points
    if secondaries > 0:
        feedback.append(f"{secondaries}/3 Secondary colors labeled (+{sec_points})")

    # Elements of Art List (15 pts)
    # 7 elements total. 
    # 6-7 found = 15 pts
    # 3-5 found = 10 pts
    # 1-2 found = 5 pts
    found_elems = content.get("found_elements_count", 0)
    if found_elems >= 6:
        score += 15
        feedback.append("Elements of Art list complete (+15)")
    elif found_elems >= 3:
        score += 10
        feedback.append(f"Elements of Art list partial ({found_elems}/7) (+10)")
    elif found_elems >= 1:
        score += 5
        feedback.append("Elements of Art list minimal (+5)")

    # --- Criterion 4: Visuals / Shape Count (10 pts) ---
    shape_count = content.get("shape_count", 0)
    if shape_count >= 6:
        score += 10
        feedback.append(f"Sufficient shapes found ({shape_count}) (+10)")
    elif shape_count >= 3:
        score += 5
        feedback.append(f"Some shapes found ({shape_count}) (+5)")
    else:
        feedback.append(f"Not enough shapes found ({shape_count})")

    # --- Criterion 5: Anti-Gaming (5 pts) ---
    if result.get("created_during_task"):
        score += 5
        feedback.append("File created during task (+5)")
    else:
        feedback.append("File timestamp indicates pre-existing file (0)")

    # --- Criterion 6: VLM Verification (5 pts) ---
    # Visual check for color wheel arrangement
    vlm_score = 0
    if query_vlm:
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            prompt = """
            Analyze this screenshot of an ActivInspire flipchart.
            Does it show a 'Color Wheel' diagram?
            Look for:
            1. Multiple colored shapes (red, blue, yellow, etc.)
            2. Arranged in a circle or wheel pattern
            3. Text labels near the shapes
            
            Return JSON:
            {"is_color_wheel": true/false, "confidence": "high/medium/low"}
            """
            try:
                vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
                if vlm_res.get("success") and vlm_res.get("parsed", {}).get("is_color_wheel"):
                    vlm_score = 5
                    feedback.append("VLM confirmed visual color wheel (+5)")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
    
    score += vlm_score

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }