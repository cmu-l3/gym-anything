#!/usr/bin/env python3
"""
Verifier for Add Watermark to Slides task.
Reads the verification result generated inside the container.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_watermark(traj, env_info, task_info):
    """
    Verify that 'DRAFT' watermark was added to all 5 slides.
    
    Scoring:
    - File Valid & Modified: 10 pts
    - Slide Count Preserved (5): 10 pts
    - Content Preserved (Titles): 10 pts
    - Watermark on Slide 1: 14 pts
    - Watermark on Slide 2: 14 pts
    - Watermark on Slide 3: 14 pts
    - Watermark on Slide 4: 14 pts
    - Watermark on Slide 5: 14 pts
    
    Total: 100 pts
    Pass Threshold: 70 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    score = 0
    feedback_parts = []
    
    # 1. File Validity & Modification (10 pts)
    if result.get("file_exists") and result.get("file_modified"):
        score += 10
        feedback_parts.append("✅ File saved and modified")
    elif result.get("file_exists"):
        score += 5
        feedback_parts.append("⚠️ File exists but not modified (did you save?)")
    else:
        feedback_parts.append("❌ File not found")
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}

    if result.get("error"):
        feedback_parts.append(f"❌ Error parsing file: {result['error']}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Slide Count (10 pts)
    slide_count = result.get("slide_count", 0)
    expected_count = task_info.get("metadata", {}).get("expected_slide_count", 5)
    
    if slide_count == expected_count:
        score += 10
        feedback_parts.append(f"✅ Slide count correct ({slide_count})")
    else:
        feedback_parts.append(f"❌ Incorrect slide count: {slide_count} (expected {expected_count})")

    # 3. Content Preservation (10 pts)
    # Require at least 4 out of 5 titles to be preserved to get points
    titles_preserved = result.get("titles_preserved", 0)
    if titles_preserved >= 4:
        score += 10
        feedback_parts.append("✅ Content preserved")
    else:
        feedback_parts.append(f"❌ Content possibly deleted ({titles_preserved}/{expected_count} titles found)")

    # 4. Watermarks (14 pts per slide)
    slides_with_draft = result.get("slides_with_draft", [])
    watermarks_found = sum(slides_with_draft)
    
    # Check each slide up to expected count
    for i in range(min(len(slides_with_draft), expected_count)):
        if slides_with_draft[i]:
            score += 14
        else:
            feedback_parts.append(f"❌ Missing 'DRAFT' on Slide {i+1}")
            
    if watermarks_found == expected_count:
        feedback_parts.append("✅ All slides have 'DRAFT' watermark")
    elif watermarks_found > 0:
        feedback_parts.append(f"⚠️ 'DRAFT' found on {watermarks_found}/{expected_count} slides")
    else:
        feedback_parts.append("❌ No 'DRAFT' watermarks found")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }