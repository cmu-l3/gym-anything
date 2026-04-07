#!/usr/bin/env python3
"""
Verifier for lipsync_drawing_substitution task.

Verifies that the agent correctly substituted drawings in the Xsheet over time.
Logic relies on the generated assets having increasing "mass" (white pixels):
Drawing 1 (Closed) < Drawing 2 (Half) < Drawing 3 (Open).

We check rendered frames at:
- Frame 5 (Should be Drawing 1 / Low Mass)
- Frame 15 (Should be Drawing 2 / Med Mass)
- Frame 25 (Should be Drawing 3 / High Mass)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lipsync_drawing_substitution(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    score = 0.0
    feedback_parts = []
    
    # 1. Output Existence (10 pts)
    if result.get("output_exists", False):
        score += 10.0
        feedback_parts.append("Output directory contains files.")
    else:
        return {"passed": False, "score": 0, "feedback": "No output files found."}

    # 2. Frame Count (10 pts)
    # Expecting 30 frames
    count = result.get("file_count", 0)
    if count >= 30:
        score += 10.0
        feedback_parts.append(f"Frame count sufficient ({count}).")
    else:
        feedback_parts.append(f"Frame count insufficient ({count}/30).")

    # 3. Content Verification (Substitution Check) (75 pts total)
    # We use mean brightness values. D1 < D2 < D3.
    # Note: Values from ImageMagick are typically 0-65535 or 0-255. We focus on relative order.
    
    m5 = float(result.get("frame_5_mean", 0))
    m15 = float(result.get("frame_15_mean", 0))
    m25 = float(result.get("frame_25_mean", 0))
    
    # Check strict ordering: m5 < m15 < m25
    # We add a small buffer to avoid noise issues, though generated assets are clean.
    
    # Frame 5 vs Frame 15 (Is 5 smaller than 15?)
    if m5 > 0 and m5 < m15:
        score += 25.0
        feedback_parts.append("Frame 5 correctly shows closed mouth (vs Frame 15).")
    else:
        feedback_parts.append(f"Frame 5/15 mismatch (Means: {m5} vs {m15}).")

    # Frame 15 vs Frame 25 (Is 15 smaller than 25?)
    if m15 > 0 and m15 < m25:
        score += 25.0
        feedback_parts.append("Frame 15 correctly shows half mouth (vs Frame 25).")
    else:
        feedback_parts.append(f"Frame 15/25 mismatch (Means: {m15} vs {m25}).")

    # Frame 25 (Open mouth) - Is it the largest?
    if m25 > m15 and m25 > m5:
        score += 25.0
        feedback_parts.append("Frame 25 correctly shows open mouth.")
    else:
        feedback_parts.append("Frame 25 is not the largest shape.")

    # 4. Anti-Gaming (5 pts)
    if result.get("files_created_during_task", False):
        score += 5.0
    else:
        feedback_parts.append("Files were not created during this task session.")

    # Final logic
    passed = score >= 75.0
    
    return {
        "passed": passed,
        "score": min(100.0, score),
        "feedback": " ".join(feedback_parts)
    }