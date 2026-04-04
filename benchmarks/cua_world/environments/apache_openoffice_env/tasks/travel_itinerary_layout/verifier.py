#!/usr/bin/env python3
"""
Verifier for travel_itinerary_layout task.

Verifies:
1. File existence and validity.
2. Landscape orientation (critical).
3. 2-Column layout (critical).
4. Images present (visual richness).
5. Content accuracy.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_travel_itinerary(traj, env_info, task_info):
    """
    Verify the travel itinerary document.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result
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

    # 1. File Existence & Timestamp (10 pts)
    if result.get("file_exists") and result.get("timestamp_valid"):
        score += 10
        feedback_parts.append("File created successfully")
    elif result.get("file_exists"):
        score += 5
        feedback_parts.append("File exists but timestamp verification failed")
    else:
        return {"passed": False, "score": 0, "feedback": "File not found"}

    # 2. Landscape Orientation (20 pts)
    if result.get("is_landscape"):
        score += 20
        feedback_parts.append("Landscape orientation applied")
    else:
        feedback_parts.append("Document is NOT in Landscape orientation")

    # 3. Columns (25 pts)
    if result.get("has_columns"):
        score += 25
        feedback_parts.append("Multi-column layout detected")
    else:
        feedback_parts.append("No multi-column layout detected")

    # 4. Images (15 pts)
    # We expect 4 images (logo + 3 destinations)
    img_count = result.get("image_count", 0)
    if img_count >= 4:
        score += 15
        feedback_parts.append(f"All images detected ({img_count})")
    elif img_count >= 1:
        score += 5
        feedback_parts.append(f"Some images missing (found {img_count})")
    else:
        feedback_parts.append("No images inserted")

    # 5. Content (20 pts)
    content_found = result.get("content_found", [])
    expected_len = 6 # defined in export script
    if len(content_found) >= expected_len:
        score += 20
        feedback_parts.append("All text content verified")
    elif len(content_found) >= 3:
        score += 10
        feedback_parts.append("Partial text content found")
    else:
        feedback_parts.append("Significant content missing")

    # 6. Heading Styles (10 pts)
    if result.get("heading_count", 0) >= 5:
        score += 10
        feedback_parts.append("Heading styles used")
    else:
        feedback_parts.append("Headings not styled properly")

    # Pass Threshold
    # Must have Orientation AND Columns to pass (core layout tasks)
    passed = score >= 70 and result.get("is_landscape") and result.get("has_columns")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }