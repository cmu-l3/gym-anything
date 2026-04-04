#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_physics_test(traj, env_info, task_info):
    """
    Verify the Physics Test Creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Exists (10 pts)
    if result.get("file_exists") and result.get("is_valid_odt"):
        score += 10
        feedback_parts.append("ODT file created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output ODT file not found or invalid."}

    # 2. Formula Objects (30 pts)
    # This is critical - they must assume Insert > Object > Formula
    formula_count = result.get("formula_count", 0)
    if formula_count >= 3:
        score += 30
        feedback_parts.append(f"Formulas inserted correctly ({formula_count} objects).")
    elif formula_count > 0:
        score += 10
        feedback_parts.append(f"Some formulas inserted, but fewer than expected ({formula_count}/3).")
    else:
        feedback_parts.append("No formula objects found. Did you type them as text instead of using the Equation Editor?")

    # 3. Image Inserted (20 pts)
    image_count = result.get("image_count", 0)
    if image_count >= 1:
        score += 20
        feedback_parts.append("Roller coaster image found.")
    else:
        feedback_parts.append("Roller coaster image missing.")

    # 4. Content Check (20 pts)
    found_text = result.get("text_content_found", [])
    required_count = 5 # defined in export script
    if len(found_text) == required_count:
        score += 20
        feedback_parts.append("All text content verified.")
    elif len(found_text) >= 3:
        score += 10
        feedback_parts.append(f"Most text content found ({len(found_text)}/{required_count}).")
    else:
        feedback_parts.append("Significant text content missing.")

    # 5. Formatting/Margins (20 pts)
    if result.get("margins_correct"):
        score += 20
        feedback_parts.append("Page margins appear correct.")
    else:
        feedback_parts.append("Page margins do not match 0.75 inches.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }