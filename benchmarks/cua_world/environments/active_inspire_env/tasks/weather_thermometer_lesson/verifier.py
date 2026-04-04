#!/usr/bin/env python3
"""
Verifier for weather_thermometer_lesson task.

Criteria:
1. File exists, is valid, and created during task.
2. Page count is exactly 2.
3. Thermometer diagram components (Circle + Rectangle shapes).
4. Specific temperature scale numbers (0, 32, 50, 70, 100).
5. Weather conditions and icons.
6. Weekly log structure (Days + Line).
7. VLM verification for thermometer visual structure.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_weather_thermometer_lesson(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve programmatic result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}

    score = 0
    feedback = []

    # 1. File Basics (20 pts)
    if result.get('file_found') and result.get('file_valid'):
        if result.get('created_during_task'):
            score += 20
            feedback.append("File created successfully (20/20)")
        else:
            score += 10
            feedback.append("File exists but timestamp verification failed (10/20)")
    else:
        feedback.append("File not found or invalid (0/20)")
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # 2. Page Count (10 pts)
    page_count = result.get('page_count', 0)
    if page_count == 2:
        score += 10
        feedback.append("Correct page count (10/10)")
    else:
        feedback.append(f"Incorrect page count: {page_count}, expected 2 (0/10)")

    # 3. Thermometer Text Scale (20 pts)
    # 0, 32, 50, 70, 100. Each worth 4 points.
    text_data = result.get('text_content', {})
    temps = ['temp_0', 'temp_32', 'temp_50', 'temp_70', 'temp_100']
    temp_hits = sum(1 for t in temps if text_data.get(t))
    temp_score = temp_hits * 4
    score += temp_score
    if temp_hits == 5:
        feedback.append("All temperature labels found (20/20)")
    else:
        feedback.append(f"Found {temp_hits}/5 temperature labels ({temp_score}/20)")

    # 4. Thermometer Shapes (15 pts)
    # Needs at least 1 Circle and 1 Rectangle
    shapes = result.get('shapes', {})
    has_circle = shapes.get('circle_count', 0) >= 1
    has_rect = shapes.get('rect_count', 0) >= 1
    
    if has_circle and has_rect:
        score += 15
        feedback.append("Thermometer shapes (Circle+Rect) found (15/15)")
    elif has_circle or has_rect:
        score += 7
        feedback.append("Partial thermometer shapes found (7/15)")
    else:
        feedback.append("Missing thermometer shapes (0/15)")

    # 5. Weather Labels (10 pts)
    if text_data.get('sunny') and text_data.get('rainy'):
        score += 10
        feedback.append("Weather condition labels found (10/10)")
    elif text_data.get('sunny') or text_data.get('rainy'):
        score += 5
        feedback.append("Partial weather labels found (5/10)")
    
    # 6. Weekly Log Structure (15 pts)
    # Mon, Wed, Fri checked in script
    days_present = sum(1 for d in ['mon', 'wed', 'fri'] if text_data.get(d))
    has_line = shapes.get('line_count', 0) >= 1
    
    log_score = 0
    if days_present >= 3: log_score += 10
    if has_line: log_score += 5
    score += log_score
    feedback.append(f"Weekly log structure score ({log_score}/15)")

    # 7. VLM Verification (10 pts)
    # Check if the thermometer actually looks like a thermometer
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if query_vlm and final_screenshot:
        prompt = """
        Analyze this screenshot of an ActivInspire flipchart.
        Look for a thermometer diagram.
        Does it contain:
        1. A vertical rectangle (stem) connected to a circle (bulb) at the bottom?
        2. Numbers listed vertically along the side (0, 32, 50, etc)?
        
        Answer with JSON: {"thermometer_visible": bool, "confidence": "high/medium/low"}
        """
        try:
            vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
            parsed = vlm_res.get('parsed', {})
            if parsed.get('thermometer_visible'):
                vlm_score = 10
                feedback.append("VLM confirmed visual thermometer structure (10/10)")
            else:
                feedback.append("VLM did not detect thermometer structure (0/10)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if we have shapes and text, give partial credit
            if has_circle and has_rect and temp_hits >= 3:
                vlm_score = 5
                feedback.append("VLM failed, assuming visual ok based on shapes (5/10)")
    
    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }