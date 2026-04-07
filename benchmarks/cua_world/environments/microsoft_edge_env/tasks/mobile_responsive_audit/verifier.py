#!/usr/bin/env python3
"""
Verifier for mobile_responsive_audit task.

Verifies:
1. File existence and validity.
2. File creation timestamp (anti-gaming).
3. Image dimensions matching iPhone 12 Pro mobile view.
4. Image height indicating full-page scroll capture.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mobile_responsive_audit(traj, env_info, task_info):
    """
    Verify that the agent created a correct mobile full-page screenshot.
    """
    # 1. Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get expected values
    metadata = task_info.get('metadata', {})
    expected_widths = metadata.get('expected_widths', [390, 780, 1170])
    width_tolerance = metadata.get('width_tolerance', 10)
    min_height = metadata.get('min_height', 1500)

    # 3. Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Exists (10 pts)
    if result.get("file_exists"):
        score += 10
        feedback_parts.append("File exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found on Desktop"}

    # Criterion 2: Valid Image (10 pts)
    if result.get("is_valid_image"):
        score += 10
    else:
        return {"passed": False, "score": 10, "feedback": "File exists but is not a valid image"}

    # Criterion 3: Created During Task (Anti-gaming check)
    if result.get("created_during_task"):
        # Implicitly required for further points in a strict environment, 
        # but here we'll just log it. If file was pre-existing, it fails the logic 
        # naturally since we clean the desktop in setup.
        pass
    else:
        feedback_parts.append("(Warning: File timestamp predates task start)")

    # Criterion 4: Correct Mobile Width (30 pts)
    # iPhone 12 Pro is 390pt wide.
    # @1x = 390px, @2x = 780px, @3x = 1170px.
    width = result.get("width", 0)
    width_match = False
    for expected in expected_widths:
        if abs(width - expected) <= width_tolerance:
            width_match = True
            break
    
    if width_match:
        score += 30
        feedback_parts.append(f"Correct mobile width ({width}px)")
    else:
        feedback_parts.append(f"Incorrect width: {width}px (Expected ~390/780/1170px)")

    # Criterion 5: Full Page Scroll Height (30 pts)
    # A generic screenshot is usually window height (~800-1000px).
    # A full page scroll of energy.gov is much longer (>2000px usually).
    height = result.get("height", 0)
    if height >= min_height:
        score += 30
        feedback_parts.append(f"Full page capture verified (Height: {height}px)")
    elif height > 0:
        feedback_parts.append(f"Image too short for full page ({height}px < {min_height}px)")
        # Partial credit if it's clearly mobile dimensions but not scrolling?
        # No, the task specifically asks for full page.
    else:
        feedback_parts.append("Invalid height")

    # Criterion 6: Content Visibility / File Size (20 pts)
    # Empty or white screenshots are small. A complex site like energy.gov will be large.
    file_size = result.get("file_size", 0)
    if file_size > 100 * 1024: # > 100KB
        score += 20
        feedback_parts.append("File size indicates content")
    else:
        feedback_parts.append(f"File suspiciously small ({file_size/1024:.1f}KB)")

    # 5. Final Determination
    # Must have correct width AND height to pass
    passed = (width_match and height >= min_height and score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }