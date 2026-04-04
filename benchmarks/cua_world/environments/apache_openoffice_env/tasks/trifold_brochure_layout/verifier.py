#!/usr/bin/env python3
"""
Verifier for trifold_brochure_layout task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_trifold_brochure(traj, env_info, task_info):
    """
    Verify the brochure creation task.
    
    Criteria:
    1. File exists (10 pts)
    2. Landscape orientation (25 pts)
    3. 3-Column layout (30 pts)
    4. Content accuracy (20 pts)
    5. Images included (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from export_result.sh
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence
    if not result.get("file_exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file 'wellness_expo_brochure.odt' was not created."
        }
    score += 10
    feedback.append("File created successfully (+10).")

    # 2. Page Orientation (Landscape)
    if result.get("is_landscape"):
        score += 25
        feedback.append("Page orientation is Landscape (+25).")
    else:
        feedback.append("Incorrect page orientation (expected Landscape).")

    # 3. Column Layout
    cols = result.get("column_count", 0)
    if cols == 3:
        score += 30
        feedback.append("3-Column layout applied (+30).")
    else:
        feedback.append(f"Incorrect column count: found {cols}, expected 3.")

    # 4. Content Verification
    found_content = result.get("content_found", [])
    expected_count = 4  # Defined in export script
    if len(found_content) == expected_count:
        score += 20
        feedback.append("All key text content found (+20).")
    elif len(found_content) > 0:
        partial = int(20 * (len(found_content) / expected_count))
        score += partial
        feedback.append(f"Partial content found ({len(found_content)}/{expected_count}) (+{partial}).")
    else:
        feedback.append("No expected text content found.")

    # 5. Images
    img_count = result.get("images_count", 0)
    if img_count >= 2:
        score += 15
        feedback.append(f"Images inserted correctly ({img_count} found) (+15).")
    elif img_count == 1:
        score += 7
        feedback.append("Only 1 image found (expected 2) (+7).")
    else:
        feedback.append("No images found in document.")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }