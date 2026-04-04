#!/usr/bin/env python3
"""
Verifier for format_code_block_slide task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_format_code_block_slide(traj, env_info, task_info):
    """
    Verify the code block slide creation and formatting.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
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

    # Extract data
    analysis = result.get('analysis', {})
    file_modified = result.get('file_modified_during_task', False)
    
    score = 0
    feedback_parts = []
    
    # 1. File Modification (10 pts)
    if file_modified:
        score += 10
        feedback_parts.append("✅ File saved")
    else:
        feedback_parts.append("❌ File not saved/modified")

    # 2. Slide Count (10 pts)
    # Expect 3 slides (started with 2)
    slide_count = analysis.get('slide_count', 0)
    if slide_count >= 3:
        score += 10
        feedback_parts.append(f"✅ Slide created (Total: {slide_count})")
    else:
        feedback_parts.append(f"❌ Slide count incorrect: {slide_count}")

    # 3. Content Verification (20 pts)
    if analysis.get('json_content_found', False):
        score += 20
        feedback_parts.append("✅ JSON content found")
    else:
        feedback_parts.append("❌ JSON content missing on last slide")

    # 4. Font Formatting (20 pts)
    if analysis.get('monospace_font_found', False):
        score += 20
        feedback_parts.append("✅ Monospace font applied")
    else:
        feedback_parts.append("❌ Monospace font not detected")

    # 5. Background Color (25 pts)
    if analysis.get('background_color_found', False):
        score += 25
        feedback_parts.append("✅ Gray background applied")
    else:
        feedback_parts.append("❌ Gray background not detected (check Area/Fill)")

    # 6. Border (15 pts)
    if analysis.get('border_found', False):
        score += 15
        feedback_parts.append("✅ Border applied")
    else:
        feedback_parts.append("❌ Border not detected")

    # Final Check
    # Pass if score >= 75 (Must have content + font + background roughly)
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }