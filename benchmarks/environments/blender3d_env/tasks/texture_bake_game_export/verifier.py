#!/usr/bin/env python3
"""
Verifier for texture_bake_game_export task.

Verification Criteria (100 points total):
1. AO Image exists, correct dimensions (15 pts)
2. AO Image has correct visual content (tonal variation, grayscale) (15 pts)
3. Diffuse Image exists, correct dimensions (15 pts)
4. Diffuse Image has correct visual content (dominant red, some variation) (15 pts)
5. Blend file exists and is valid (15 pts)
6. Blend file internal state (Cycles engine, image nodes present) (10 pts)
7. Anti-gaming: Files created after task start (10 pts)
8. File size sanity check (5 pts)

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_texture_bake_game_export(traj, env_info, task_info):
    """
    Verify the texture baking task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read task result: {e}. The export script may have failed."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. AO Image Basics (15 pts)
    ao = result.get("ao_image", {})
    if ao.get("exists") and ao.get("width") == 1024 and ao.get("height") == 1024:
        score += 15
        feedback_parts.append("AO Map: Exists & Correct Size")
    elif ao.get("exists"):
        score += 5
        feedback_parts.append(f"AO Map: Exists but wrong size ({ao.get('width')}x{ao.get('height')})")
    else:
        feedback_parts.append("AO Map: Missing")

    # 2. AO Content Quality (15 pts)
    # Expecting some standard deviation (not flat color) and reasonable brightness
    ao_std = ao.get("pixel_std", 0)
    ao_mean = ao.get("pixel_mean", 0)
    if ao.get("exists"):
        if ao_std > 5.0 and 50 < ao_mean < 250:
            score += 15
            feedback_parts.append("AO Map: Good tonal variation")
        else:
            feedback_parts.append(f"AO Map: Content invalid (std={ao_std:.1f}, mean={ao_mean:.1f})")

    # 3. Diffuse Image Basics (15 pts)
    diff = result.get("diffuse_image", {})
    if diff.get("exists") and diff.get("width") == 1024 and diff.get("height") == 1024:
        score += 15
        feedback_parts.append("Diffuse Map: Exists & Correct Size")
    elif diff.get("exists"):
        score += 5
        feedback_parts.append("Diffuse Map: Exists but wrong size")
    else:
        feedback_parts.append("Diffuse Map: Missing")

    # 4. Diffuse Content Quality (15 pts)
    # Expecting Red dominant and some variation (from UV seams/noise)
    diff_red_dom = diff.get("red_dominant", False)
    diff_std = diff.get("pixel_std", 0)
    if diff.get("exists"):
        if diff_red_dom and diff_std > 0.5:
            score += 15
            feedback_parts.append("Diffuse Map: Correct Color & Content")
        elif diff_red_dom:
            score += 10
            feedback_parts.append("Diffuse Map: Correct Color but flat (no UV seams?)")
        else:
            feedback_parts.append("Diffuse Map: Wrong color (not red)")

    # 5. Blend File Basics (15 pts)
    blend = result.get("blend_file", {})
    if blend.get("exists") and blend.get("valid_magic"):
        score += 15
        feedback_parts.append("Project: Saved & Valid")
    elif blend.get("exists"):
        score += 5
        feedback_parts.append("Project: File exists but invalid")
    else:
        feedback_parts.append("Project: Missing")

    # 6. Blend File State (10 pts)
    if blend.get("exists"):
        if blend.get("render_engine") == "CYCLES" and blend.get("has_image_nodes"):
            score += 10
            feedback_parts.append("Project: Cycles & Nodes Setup Correctly")
        elif blend.get("render_engine") == "CYCLES":
            score += 5
            feedback_parts.append("Project: Cycles Set, Missing Image Nodes")
        else:
            feedback_parts.append(f"Project: Wrong Engine ({blend.get('render_engine')})")

    # 7. Anti-gaming: Timestamp (10 pts)
    if result.get("timestamp_check_passed", False):
        score += 10
        feedback_parts.append("Anti-gaming: Timestamps Valid")
    else:
        feedback_parts.append("Anti-gaming: Files older than task start")

    # 8. File Size Sanity (5 pts)
    ao_size = ao.get("size_bytes", 0)
    diff_size = diff.get("size_bytes", 0)
    if ao_size > 5000 and diff_size > 5000:
        score += 5
        feedback_parts.append("File sizes OK")
    else:
        if ao.get("exists") or diff.get("exists"):
            feedback_parts.append("Warning: Files suspiciously small")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }