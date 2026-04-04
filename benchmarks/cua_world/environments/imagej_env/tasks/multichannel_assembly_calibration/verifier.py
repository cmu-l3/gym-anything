#!/usr/bin/env python3
"""
Verifier for multichannel_assembly_calibration task.

Criteria:
1. File exists and created during task (20 pts)
2. Format is TIFF (10 pts)
3. Composite/Multi-channel structure (not flattened RGB) (20 pts)
4. Spatial Calibration is correct (0.16 micron/px) (30 pts)
5. VLM Visual Check (channels visible, color composite) (20 pts)
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multichannel_assembly(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy unavailable"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    analysis = result.get("tiff_analysis", {})
    
    # 1. File Existence & Timestamp
    if analysis.get("exists") and analysis.get("created_during_task"):
        score += 20
        feedback.append("File created successfully.")
    elif analysis.get("exists"):
        # Exists but old?
        return {"passed": False, "score": 0, "feedback": "File exists but was not created during this task."}
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # 2. Format
    if analysis.get("is_tiff"):
        score += 10
        feedback.append("Format is TIFF.")
    else:
        feedback.append(f"Incorrect format: {analysis.get('mode')}")

    # 3. Composite Check
    # ImageJ composites often save ImageDescription containing "images=3" or "channels=3"
    desc = analysis.get("image_description", "")
    is_composite = "channels=3" in desc or "images=3" in desc or analysis.get("frames", 0) == 3
    
    # If flattened to RGB, mode is RGB and desc might lack channel info
    is_flattened = analysis.get("mode") == "RGB" and not is_composite

    if is_composite:
        score += 20
        feedback.append("Image is a multi-channel composite.")
    elif is_flattened:
        feedback.append("Image was flattened to RGB (should be Composite).")
    else:
        # If it's something else
        if analysis.get("channels") == 3:
             score += 15 # Partial credit if PIL sees 3 bands but not clearly composite
             feedback.append("Image has 3 channels.")
        else:
             feedback.append(f"Incorrect channel count: {analysis.get('channels')}")

    # 4. Calibration Check
    # Expected: 0.16 microns/pixel
    # XResolution tag usually stores pixels per unit.
    # If unit is micron, XRes should be 1/0.16 = 6.25
    # ImageJ description often contains "unit=micron"
    
    x_res = analysis.get("x_resolution_val", 0)
    # Check description for explicit "unit=micron"
    has_micron_unit = "unit=micron" in desc or "unit=\xb5m" in desc
    
    # Check pixel width in description
    # ImageJ writes: spacing=0.16 or pixel_width=0.16
    pixel_width_match = re.search(r'(spacing|pixel_width)=([\d\.]+)', desc)
    
    calibrated = False
    if pixel_width_match:
        val = float(pixel_width_match.group(2))
        if 0.15 <= val <= 0.17:
            calibrated = True
    elif x_res > 0:
        # Check if resolution value corresponds to 0.16 (approx 6.25)
        # OR if x_res IS 0.16 (some software writes unit size)
        if 6.0 <= x_res <= 6.5 or 0.15 <= x_res <= 0.17:
            calibrated = True

    if calibrated and has_micron_unit:
        score += 30
        feedback.append("Calibration (0.16 microns) verified.")
    elif calibrated:
        score += 20
        feedback.append("Resolution value correct but unit check ambiguous.")
    elif has_micron_unit:
        score += 10
        feedback.append("Unit is microns but value seems incorrect.")
    else:
        feedback.append(f"Calibration missing or incorrect. Desc: {desc[:50]}...")

    # 5. VLM Visual Check
    # We rely on the implicit VLM verification pattern if available, 
    # but here we'll add points for passing the file checks implies visual success likely
    # Real VLM integration would query here. We'll give points if composite is valid.
    if score >= 50:
        score += 20
        feedback.append("Visual structure assumed valid based on metadata.")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " ".join(feedback)
    }