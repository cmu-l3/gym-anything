#!/usr/bin/env python3
"""
Verifier for web_image_optimization@1
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_web_image_optimization(traj, env_info, task_info):
    """
    Verifies that the agent optimized the image correctly using Squoosh.
    
    Criteria:
    1. Output file exists and was created during task (Anti-gaming).
    2. Format is WebP.
    3. Width is 1280px (tolerance +/- 2px).
    4. File size is significantly compressed compared to source.
    5. Tool (squoosh.app) was visited.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

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

    # 2. Extract Metadata
    metadata = task_info.get('metadata', {})
    target_width = metadata.get('target_width', 1280)
    width_tolerance = metadata.get('width_tolerance', 2)
    
    # 3. Evaluate Criteria
    score = 0
    feedback = []
    
    # Criterion A: File Existence & Timestamp (20 pts)
    exists = result.get('output_exists', False)
    fresh = result.get('created_after_start', False)
    
    if exists and fresh:
        score += 20
        feedback.append("Output file created successfully.")
    elif exists:
        score += 5
        feedback.append("Output file exists but has old timestamp (pre-existing?).")
    else:
        feedback.append("Output file not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion B: Format (20 pts)
    # ImageMagick identifies WebP as 'WEBP'
    fmt = result.get('format', '').upper()
    if 'WEBP' in fmt:
        score += 20
        feedback.append("Correct file format (WebP).")
    else:
        feedback.append(f"Incorrect file format: {fmt} (Expected WebP).")

    # Criterion C: Dimensions (30 pts)
    actual_width = result.get('width', 0)
    width_diff = abs(actual_width - target_width)
    
    if width_diff <= width_tolerance:
        score += 30
        feedback.append(f"Correct width: {actual_width}px.")
    elif actual_width > 0:
        # Partial credit if close (e.g. within 10%)
        if abs(actual_width - target_width) < (target_width * 0.1):
             score += 10
             feedback.append(f"Width {actual_width}px is close but not exact (Target {target_width}px).")
        else:
             feedback.append(f"Incorrect width: {actual_width}px (Target {target_width}px).")
    else:
        feedback.append("Could not determine image width.")

    # Criterion D: Compression (10 pts)
    # Source was huge (PNG), output should be WebP. Expect significant reduction.
    size = result.get('size_bytes', 0)
    source_size = result.get('source_size_bytes', 1) # avoid div by zero
    
    if source_size > 0:
        ratio = size / source_size
        if ratio < 0.5: # Expecting at least 50% reduction for PNG -> WebP resize
            score += 10
            feedback.append("Good compression achieved.")
        else:
            feedback.append(f"Compression ratio poor ({ratio:.2f}).")
            
    # Criterion E: Tool Usage (10 pts)
    if result.get('visited_tool', False):
        score += 10
        feedback.append("Verified visit to squoosh.app.")
    else:
        feedback.append("Did not detect visit to squoosh.app in history.")

    # Criterion F: Trajectory Verification (10 pts)
    # Simple check: did they actually do it?
    # We implicitly trust the file result more, but let's give points for VLM pass if we had it.
    # Since we don't have VLM in this basic verifier, we allocate the last 10 points 
    # based on perfect execution of previous steps.
    if score >= 80:
        score += 10
        feedback.append("Bonus: High quality execution.")

    passed = (score >= 70) and exists and fresh
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }