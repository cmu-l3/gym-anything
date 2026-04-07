#!/usr/bin/env python3
"""
Verifier for pipeline_test_card_render task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pipeline_test_card_render(traj, env_info, task_info):
    """
    Verify that the agent created a render test card.
    
    Criteria:
    1. Output file exists (20 pts)
    2. File created during task (15 pts)
    3. Dimensions reasonable (>= 400x300) (15 pts)
    4. Image is not blank (contains drawn content) (30 pts)
    5. Substantial content (>= 1% non-background) (10 pts)
    6. File size > 1KB (10 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check file existence
    if result.get("file_exists", False):
        score += 20
        feedback_parts.append("Output file found")
    else:
        feedback_parts.append("Output file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check creation time (Anti-gaming)
    if result.get("file_created_during_task", False):
        score += 15
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File is old (pre-existing)")

    # 3. Check dimensions
    width = result.get("image_width", 0)
    height = result.get("image_height", 0)
    if width >= 400 and height >= 300:
        score += 15
        feedback_parts.append(f"Dimensions OK ({width}x{height})")
    else:
        feedback_parts.append(f"Dimensions too small ({width}x{height})")

    # 4. Check for blank image (Unique colors)
    # A blank image usually has 1 color. A drawn image has at least 2 (bg + stroke).
    # Antialiasing adds more.
    unique_colors = result.get("unique_colors", 0)
    if unique_colors >= 2:
        score += 30
        feedback_parts.append("Image is not blank")
    else:
        feedback_parts.append("Image appears blank (single color)")

    # 5. Check content ratio (Substantial content)
    ratio = result.get("non_bg_ratio", 0.0)
    # 0.5% coverage is enough to be a shape, 0.0% is empty
    if ratio > 0.005: 
        score += 10
        feedback_parts.append(f"Content visible ({ratio*100:.2f}% coverage)")
    else:
        feedback_parts.append(f"Content minimal/empty ({ratio*100:.2f}% coverage)")

    # 6. Check file size
    size_bytes = result.get("file_size_bytes", 0)
    if size_bytes > 1024:
        score += 10
        feedback_parts.append("File size OK")
    else:
        feedback_parts.append("File too small")

    passed = score >= 60 and result.get("file_exists", False) and unique_colors >= 2

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }