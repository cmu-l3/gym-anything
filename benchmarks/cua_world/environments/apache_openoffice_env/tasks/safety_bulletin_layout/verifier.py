#!/usr/bin/env python3
"""
Verifier for safety_bulletin_layout task.
Scores the ODT document based on XML structure analysis.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_safety_bulletin(traj, env_info, task_info):
    """
    Verify the safety bulletin ODT file.
    Criteria:
    - File exists & valid ODT (10pts)
    - 2-Column layout used (25pts)
    - Image inserted (15pts)
    - Text wrapping enabled (20pts)
    - Bordered box present (15pts)
    - Bullet points used (10pts)
    - Content copied correctly (5pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # 1. File Existence (10pts)
    if result.get("file_exists") and result.get("timestamp_valid"):
        score += 10
        feedback_parts.append("File created successfully")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found or not created during task"}

    # 2. Columns (25pts)
    if result.get("columns_detected"):
        score += 25
        feedback_parts.append("Two-column layout detected")
    else:
        feedback_parts.append("Missing two-column layout")

    # 3. Image Insertion (15pts)
    if result.get("image_present"):
        score += 15
        feedback_parts.append("Image inserted")
    else:
        feedback_parts.append("No image found")

    # 4. Text Wrapping (20pts)
    # Only award if image is also present
    if result.get("image_present") and result.get("wrapping_enabled"):
        score += 20
        feedback_parts.append("Text wrapping enabled")
    elif result.get("image_present"):
        feedback_parts.append("Image found but text wrapping (flow around) not detected")

    # 5. Borders (15pts)
    if result.get("borders_detected"):
        score += 15
        feedback_parts.append("Bordered section detected")
    else:
        feedback_parts.append("No borders/boxes detected")

    # 6. Bullet Points (10pts)
    if result.get("bullet_points_detected"):
        score += 10
        feedback_parts.append("Bullet points detected")
    else:
        feedback_parts.append("List formatting missing")

    # 7. Content Check (5pts)
    if result.get("content_match"):
        score += 5
    else:
        feedback_parts.append("Some text content appears missing")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }