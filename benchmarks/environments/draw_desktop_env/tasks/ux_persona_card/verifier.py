#!/usr/bin/env python3
"""
Verifier for ux_persona_card task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ux_persona_card(traj, env_info, task_info):
    """
    Score the Persona Card task based on:
    1. File Creation (10pts)
    2. Image Import (20pts)
    3. Text Content (20pts)
    4. Custom Visuals/Sliders (25pts)
    5. Grouping (10pts)
    6. PNG Export (15pts)
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy unavailable"}

    # 2. Copy result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion 1: File Saved (10)
    if result.get("drawio_exists") and result.get("file_timestamp_valid"):
        score += 10
        feedback.append("File saved successfully.")
    else:
        feedback.append("File not found or not modified.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Image Import (20)
    if result.get("image_embedded"):
        score += 20
        feedback.append("Image imported.")
    else:
        feedback.append("Missing profile photo.")

    # Criterion 3: Text Content (20)
    # Check for key phrases
    found_texts = result.get("text_content_found", [])
    required_count = 4 # Penny, Parker, Project Manager, etc.
    if len(found_texts) >= required_count:
        score += 20
        feedback.append(f"Text content verified ({len(found_texts)} matches).")
    elif len(found_texts) > 0:
        score += 10
        feedback.append(f"Partial text matches ({len(found_texts)}).")
    else:
        feedback.append("Key text content missing.")

    # Criterion 4: Sliders (25)
    # Complex visual construction check
    sliders = result.get("slider_widgets_count", 0)
    if sliders >= 3:
        score += 25
        feedback.append("Personality sliders created correctly.")
    elif sliders >= 1:
        score += 10
        feedback.append("Partial sliders detected.")
    else:
        feedback.append("Missing personality slider widgets (requires lines + circles).")

    # Criterion 5: Grouping (10)
    if result.get("grouping_used"):
        score += 10
        feedback.append("Grouping used.")
    else:
        feedback.append("Elements not grouped.")

    # Criterion 6: PNG Export (15)
    if result.get("png_exists") and result.get("png_valid"):
        score += 15
        feedback.append("PNG exported.")
    else:
        feedback.append("PNG export missing or empty.")

    # 4. Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }