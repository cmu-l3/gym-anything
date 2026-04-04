#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_spur_gear(traj, env_info, task_info):
    """
    Verifies the creation of a 24-tooth, module 2.0, 10mm thick spur gear with 12mm bore.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function unavailable"}

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Define Criteria and Scoring
    score = 0
    feedback = []
    
    # Metadata parameters (Ground Truth)
    # Teeth=24, Mod=2.0, Thickness=10, BoreRadius=6
    # Tip Diameter = M * (N + 2) = 2.0 * 26 = 52.0 mm
    # Root Diameter = M * (N - 2.5) = 2.0 * 21.5 = 43.0 mm (approx, depends on clearance)
    # Pitch Diameter = M * N = 48.0 mm
    
    EXPECTED_BBOX_XY = 52.0
    EXPECTED_THICKNESS = 10.0
    TOLERANCE_XY = 1.0  # Allow 1mm variance
    TOLERANCE_Z = 0.5   # Allow 0.5mm variance
    
    # Volume Estimation
    # A standard 24T Mod2 gear volume is roughly 16,000 - 18,000 mm^3 (solid) minus the hole.
    # Hole Volume = pi * r^2 * h = pi * 36 * 10 ≈ 1131 mm^3
    # Let's look for volume > 10,000 mm^3 as a sanity check for "substantial solid"
    # and < 25,000 mm^3 to ensure they didn't just make a giant block.
    # Precise volume isn't strictly necessary if BBox and Topology are correct.
    MIN_VOLUME = 10000
    MAX_VOLUME = 25000

    # Criterion A: File Exists & Valid Solid (25 pts)
    if result.get("file_exists") and result.get("valid_solid"):
        score += 25
        feedback.append("Valid solid object found")
    else:
        feedback.append("No valid solid object found in output file")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback)}

    # Criterion B: Bounding Box Dimensions (40 pts)
    # Gear should be circular-ish in XY, so X length ≈ Y length ≈ 52mm
    bbox = result.get("bbox", [0, 0, 0])
    x_len, y_len, z_len = bbox[0], bbox[1], bbox[2]
    
    xy_match = abs(x_len - EXPECTED_BBOX_XY) < TOLERANCE_XY and \
               abs(y_len - EXPECTED_BBOX_XY) < TOLERANCE_XY
               
    z_match = abs(z_len - EXPECTED_THICKNESS) < TOLERANCE_Z
    
    if xy_match:
        score += 20
        feedback.append(f"Diameter correct (~{EXPECTED_BBOX_XY}mm)")
    else:
        feedback.append(f"Diameter incorrect (Expected ~{EXPECTED_BBOX_XY}mm, Got {x_len:.1f}x{y_len:.1f}mm)")
        
    if z_match:
        score += 20
        feedback.append(f"Thickness correct (~{EXPECTED_THICKNESS}mm)")
    else:
        feedback.append(f"Thickness incorrect (Expected {EXPECTED_THICKNESS}mm, Got {z_len:.1f}mm)")

    # Criterion C: Volume/Shape Sanity (20 pts)
    # This catches if they just made a cylinder (Box would fail XY match usually, or match poorly)
    # The Cut operation (hole) removes ~1131 mm^3.
    vol = result.get("volume", 0)
    if MIN_VOLUME < vol < MAX_VOLUME:
        score += 20
        feedback.append("Volume within reasonable range for a gear")
    else:
        feedback.append(f"Volume out of range ({vol:.0f} mm^3)")

    # Criterion D: Procedural History / Tool Usage (15 pts)
    # Did they use the Involute tool or just draw circles?
    if result.get("has_involute_history"):
        score += 15
        feedback.append("Involute generator usage detected")
    else:
        feedback.append("Involute generator usage NOT detected (manual sketch?)")
    
    # Anti-Gaming check (Pass/Fail override)
    if not result.get("file_created_during_task"):
        score = 0
        feedback = ["File not modified during task duration"]

    passed = score >= 70 and xy_match and z_match
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback)
    }