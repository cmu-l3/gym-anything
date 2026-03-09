#!/usr/bin/env python3
"""
Verifier for render_passes_exr_export task.

Scoring Breakdown (100 pts total):
1. Enabled Render Passes (60 pts, 10 per pass)
   - Z (Depth)
   - Mist
   - Normal
   - Diffuse Color
   - Glossy Direct
   - Ambient Occlusion
2. Output Settings (15 pts)
   - Format: OPEN_EXR_MULTILAYER (10)
   - Depth: 32-bit (5)
3. Output Files (25 pts)
   - EXR file exists, is valid, size > 500KB, created during task (15)
   - Blend file exists (10)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_render_passes_exr_export(traj, env_info, task_info):
    """
    Verify render passes and EXR export configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_passes = metadata.get('required_passes', [])
    
    # 1. Copy result JSON
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
    feedback = []

    # ---------------------------------------------------------
    # Criteria 1: Render Passes (60 pts)
    # ---------------------------------------------------------
    passes = result.get("passes", {})
    pass_score = 0
    
    # Map friendly names for feedback
    pass_names = {
        "use_pass_z": "Depth (Z)",
        "use_pass_mist": "Mist",
        "use_pass_normal": "Normal",
        "use_pass_diffuse_color": "Diffuse Color",
        "use_pass_glossy_direct": "Glossy Direct",
        "use_pass_ambient_occlusion": "Ambient Occlusion"
    }

    for p in required_passes:
        if passes.get(p):
            pass_score += 10
        else:
            feedback.append(f"Missing pass: {pass_names.get(p, p)}")
    
    score += pass_score
    if pass_score == 60:
        feedback.append("All required render passes enabled (+60)")
    else:
        feedback.append(f"Render passes score: {pass_score}/60")

    # ---------------------------------------------------------
    # Criteria 2: Output Settings (15 pts)
    # ---------------------------------------------------------
    settings = result.get("output_settings", {})
    
    # Format (10)
    fmt = settings.get("file_format", "UNKNOWN")
    if fmt == "OPEN_EXR_MULTILAYER":
        score += 10
        feedback.append("Format is OpenEXR MultiLayer (+10)")
    else:
        feedback.append(f"Wrong format: {fmt} (Expected OPEN_EXR_MULTILAYER)")

    # Depth (5)
    depth = settings.get("color_depth", "UNKNOWN")
    if depth == "32":
        score += 5
        feedback.append("Color depth is 32-bit Float (+5)")
    else:
        feedback.append(f"Wrong color depth: {depth} (Expected 32)")

    # ---------------------------------------------------------
    # Criteria 3: Output Files (25 pts)
    # ---------------------------------------------------------
    # Blend file (10)
    if result.get("blend_exists"):
        score += 10
        feedback.append("Project file saved (+10)")
    else:
        feedback.append("Project file NOT saved")

    # EXR File (15)
    # Must be valid, fresh, and large enough (to prove it contains layers)
    exr_exists = result.get("exr_exists")
    exr_valid = result.get("exr_valid")
    exr_fresh = result.get("exr_fresh")
    exr_size = result.get("exr_size_kb", 0)
    min_size = metadata.get("min_exr_size_kb", 500)

    if exr_exists and exr_valid and exr_fresh and exr_size > min_size:
        score += 15
        feedback.append(f"EXR render verified ({int(exr_size)}KB) (+15)")
    else:
        reasons = []
        if not exr_exists: reasons.append("not found")
        elif not exr_valid: reasons.append("invalid header")
        elif not exr_fresh: reasons.append("old timestamp")
        elif exr_size <= min_size: reasons.append(f"too small: {int(exr_size)}KB")
        feedback.append(f"EXR render failed: {', '.join(reasons)}")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "; ".join(feedback)
    }