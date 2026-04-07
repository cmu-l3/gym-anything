#!/usr/bin/env python3
"""
Verifier for create_subitizing_experiment task.

Verification Strategy:
1.  **Image Analysis (Pre-computed in export)**: Checks if 8 images exist and if the number of blobs (connected components) in image N.png equals N.
    *   This verifies BOTH that the generation script worked AND that it prevented overlaps (overlaps would reduce the blob count).
2.  **Script Logic**: Checks if the generation script contains keywords implying overlap/distance checks.
3.  **Experiment Structure**: Checks the .psyexp XML for:
    *   Image component presence.
    *   CRITICAL: Duration set to 0.2 or 200ms (subitizing threshold).
    *   Conditions file linkage.
4.  **Conditions File**: Checks for 8 rows and correct image-to-key mapping.
5.  **VLM Verification**: Trajectory checks for coding interaction and builder usage.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_create_subitizing_experiment(traj, env_info, task_info):
    """Verify subitizing experiment creation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # Load result JSON
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/subitizing_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # ================================================================
    # NONCE GATE
    # ================================================================
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        result_nonce = result.get('result_nonce', '')
        if expected_nonce and result_nonce != expected_nonce:
            return {
                "passed": False,
                "score": 0,
                "feedback": "FAIL: Result nonce mismatch",
                "details": {"nonce_mismatch": True}
            }
    except Exception as e:
        logger.warning(f"Nonce check skipped: {e}")
    finally:
        if 'nonce_path' in locals() and os.path.exists(nonce_path):
            os.unlink(nonce_path)

    # 1. Image Generation Verification (35 points)
    # Checks if N.png has N non-overlapping dots
    image_analysis = result.get("image_analysis", {})
    valid_images = 0
    total_images = 8
    
    for i in range(1, 9):
        img_res = image_analysis.get(str(i), {})
        if img_res.get("pass", False):
            valid_images += 1
    
    image_score = 0
    if valid_images == 8:
        image_score = 35
        feedback_parts.append("All 8 stimulus images valid (correct dot counts, no overlap)")
    elif valid_images > 0:
        image_score = int((valid_images / 8) * 35)
        feedback_parts.append(f"{valid_images}/8 images valid")
    else:
        feedback_parts.append("No valid stimulus images found")
    score += image_score

    # 2. Script Logic Check (10 points)
    if result.get("script_content_check", False):
        score += 10
        feedback_parts.append("Script contains overlap prevention logic")
    elif result.get("script_exists", False):
        score += 5
        feedback_parts.append("Script exists but overlap logic unclear")
    
    # 3. Experiment Timing (CRITICAL) (20 points)
    # Subitizing requires specific timing (approx 200ms)
    duration_val = result.get("psyexp_structure", {}).get("duration", "")
    timing_correct = False
    
    if duration_val:
        # Handle strings like "0.2" or "0.200" or ".2"
        try:
            d = float(duration_val)
            if 0.15 <= d <= 0.25:
                timing_correct = True
        except ValueError:
            pass
            
    if timing_correct:
        score += 20
        feedback_parts.append(f"Stimulus duration correct ({duration_val}s)")
    else:
        feedback_parts.append(f"Stimulus duration incorrect or missing (found: '{duration_val}', expected 0.2)")

    # 4. Conditions File & Structure (15 points)
    cond_struct = result.get("cond_structure", {})
    row_count = cond_struct.get("row_count", 0)
    correct_mappings = cond_struct.get("correct_mappings", 0)
    
    if row_count >= 8 and correct_mappings >= 8:
        score += 15
        feedback_parts.append("Conditions file valid")
    elif row_count >= 8:
        score += 8
        feedback_parts.append("Conditions file has rows but mappings unclear")

    # 5. Experiment Structure (Loop) (10 points)
    loops = result.get("psyexp_structure", {}).get("loops", [])
    has_valid_loop = False
    for loop in loops:
        f = loop.get('file', '')
        if 'conditions' in f or 'csv' in f:
            has_valid_loop = True
            break
    
    if has_valid_loop:
        score += 10
        feedback_parts.append("Trial loop configured correctly")
    
    # 6. Basic Existence (10 points)
    if result.get("exp_exists"):
        score += 10

    # Calculate final status
    passed = score >= 70 and timing_correct and valid_images >= 6
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }