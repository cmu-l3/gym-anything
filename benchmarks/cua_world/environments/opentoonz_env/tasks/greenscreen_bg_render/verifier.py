#!/usr/bin/env python3
"""
Verifier for greenscreen_bg_render task.

Criteria:
1. Output Existence (20 pts): >= 10 frames found.
2. Anti-Gaming (20 pts): Files created AFTER task start.
3. Content Verification (45 pts): Background pixels match Green (#00FF00).
4. File Properties (15 pts): Reasonable file size and consistent dimensions.

Pass Threshold: 60/100
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_greenscreen_bg_render(traj, env_info, task_info):
    # 1. Setup & Retrieve Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    png_count = result.get("png_count", 0)
    newer_count = result.get("newer_than_start", 0)
    total_size = result.get("total_size_bytes", 0)
    pixel_data = result.get("pixel_analysis", {})
    green_score = pixel_data.get("green_score", 0.0) # 0.0 to 1.0
    dims = pixel_data.get("dimensions", [0, 0])
    
    # CRITERION 1: Frame Count (20 pts)
    if png_count >= 10:
        score += 20
        feedback_parts.append(f"Frame count OK ({png_count})")
    elif png_count > 0:
        # Partial credit
        pts = int(20 * (png_count / 10))
        score += pts
        feedback_parts.append(f"Low frame count ({png_count}/10)")
    else:
        feedback_parts.append("No output frames found")

    # CRITERION 2: Anti-Gaming / Timestamp Check (20 pts)
    if newer_count >= 10:
        score += 20
        feedback_parts.append("All files created during task")
    elif newer_count > 0:
        pts = int(20 * (newer_count / 10))
        score += pts
        feedback_parts.append(f"Some pre-existing files detected ({newer_count} new)")
    else:
        feedback_parts.append("No new files created")

    # CRITERION 3: Content Verification - Green Background (45 pts)
    # green_score is fraction of sampled edge pixels that were green
    if green_score >= 0.9:
        score += 45
        feedback_parts.append("Background is solid green")
    elif green_score >= 0.5:
        # Partial credit (maybe some frames failed or noise)
        pts = int(45 * green_score)
        score += pts
        feedback_parts.append(f"Background mostly green (score: {green_score:.2f})")
    else:
        feedback_parts.append(f"Background NOT green (score: {green_score:.2f})")

    # CRITERION 4: File Properties (15 pts)
    props_score = 0
    # Size check (>100KB total implies actual content)
    if total_size > 100 * 1024:
        props_score += 10
    
    # Dimension check
    if dims and dims[0] > 0:
        props_score += 5
        
    score += props_score
    if props_score < 15:
        feedback_parts.append("File size/dimensions suspicious")
    else:
        feedback_parts.append("File properties OK")

    # Final Result
    # Must have at least some green frames and created new files to pass
    passed = (score >= 60) and (green_score > 0.5) and (newer_count > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }