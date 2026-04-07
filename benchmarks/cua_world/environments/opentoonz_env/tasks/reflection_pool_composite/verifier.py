#!/usr/bin/env python3
"""
Verifier for reflection_pool_composite task.

Criteria:
1. Files exist and created during task.
2. Resolution is 1920x1080.
3. Content exists in Top Half (Character).
4. Content exists in Bottom Half (Reflection).
5. Reflection is semi-transparent (Bottom Alpha < Top Alpha).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reflection_pool_composite(traj, env_info, task_info):
    # Setup copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # Extract metrics
    file_count = result.get('file_count', 0)
    created_new = result.get('files_created_during_task', False)
    width = result.get('width', 0)
    height = result.get('height', 0)
    top_alpha = result.get('top_alpha_avg', 0)
    bottom_alpha = result.get('bottom_alpha_avg', 0)
    top_coverage = result.get('top_coverage', 0)
    bottom_coverage = result.get('bottom_coverage', 0)

    # Criterion 1: Files Generated (10 pts)
    if file_count >= 10:
        score += 10
        feedback_parts.append(f"Generated {file_count} frames")
    elif file_count > 0:
        score += 5
        feedback_parts.append(f"Generated only {file_count} frames (expected >= 10)")
    else:
        feedback_parts.append("No output files found")

    # Criterion 2: Anti-gaming (10 pts)
    if created_new:
        score += 10
    elif file_count > 0:
        feedback_parts.append("Files detected but old timestamps (not created during task)")

    # Criterion 3: Resolution 1920x1080 (20 pts)
    if width == 1920 and height == 1080:
        score += 20
        feedback_parts.append("Resolution correct (1920x1080)")
    else:
        feedback_parts.append(f"Incorrect resolution: {width}x{height}")

    # Criterion 4: Composition Check (40 pts split)
    # Check Top Half Content
    if top_coverage > 0.01:  # At least 1% pixels have content
        score += 10
        feedback_parts.append("Character detected in top half")
        
        # Check Top Opacity (Should be mostly opaque ~255)
        if top_alpha > 200:
            score += 10
            feedback_parts.append("Top character is opaque")
        else:
            feedback_parts.append(f"Top character unusually transparent (avg alpha {top_alpha:.1f})")
    else:
        feedback_parts.append("Top half is empty")

    # Check Bottom Half Content (Reflection)
    if bottom_coverage > 0.01:
        score += 10
        feedback_parts.append("Reflection detected in bottom half")
    else:
        feedback_parts.append("Bottom half is empty (no reflection)")

    # Criterion 5: Reflection Transparency (20 pts)
    # Bottom alpha should be significantly lower than Top alpha (e.g., < 80% of top)
    # And not fully opaque (should be < 240)
    if bottom_coverage > 0.01 and top_coverage > 0.01:
        if bottom_alpha < (top_alpha * 0.85) and bottom_alpha < 240:
            score += 20
            feedback_parts.append(f"Reflection transparency good (Top: {top_alpha:.0f}, Bottom: {bottom_alpha:.0f})")
        elif bottom_alpha > 240:
             feedback_parts.append("Reflection is fully opaque (missed transparency step)")
        else:
             feedback_parts.append(f"Reflection alpha ({bottom_alpha:.0f}) not distinct enough from top ({top_alpha:.0f})")

    passed = score >= 70 and width == 1920 and height == 1080
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }