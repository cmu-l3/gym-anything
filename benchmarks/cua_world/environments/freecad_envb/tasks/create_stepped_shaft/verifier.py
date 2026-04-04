#!/usr/bin/env python3
"""
Verifier for create_stepped_shaft task.

CRITERIA:
1. File exists and valid (10 pts)
2. Created during task (5 pts)
3. Single solid body (15 pts)
4. Correct Bounding Box dimensions (30 pts)
5. Correct Volume (20 pts)
6. Correct Cross-section diameters (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_stepped_shaft(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    
    # Check 1: File Existence (10 pts)
    if result.get("file_exists"):
        score += 10
        feedback.append("File exists.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # Check 2: Timestamp (5 pts)
    if result.get("file_created_during_task"):
        score += 5
    else:
        feedback.append("Warning: File timestamp indicates pre-existing file.")

    # Geometry Analysis
    geo = result.get("geometry_analysis", {})
    if not geo or not geo.get("valid_geometry"):
        feedback.append("Failed to analyze geometry or no solid found.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Check 3: Single Solid (15 pts)
    n_solids = geo.get("n_solids", 0)
    if n_solids == 1:
        score += 15
        feedback.append("Single solid body verified.")
    else:
        feedback.append(f"Found {n_solids} solids (expected 1).")

    # Check 4: Bounding Box (30 pts)
    # Target: Height 60mm, Width/Depth ~12mm
    bbox = geo.get("bbox", {})
    z_len = bbox.get("z", 0)
    xy_max = max(bbox.get("x", 0), bbox.get("y", 0))

    if abs(z_len - 60.0) < 1.0:
        score += 15
        feedback.append("Height correct.")
    else:
        feedback.append(f"Height incorrect ({z_len:.1f}mm vs 60mm).")

    if abs(xy_max - 12.0) < 1.0:
        score += 15
        feedback.append("Max diameter correct.")
    else:
        feedback.append(f"Max diameter incorrect ({xy_max:.1f}mm vs 12mm).")

    # Check 5: Volume (20 pts)
    # Expected: ~5152 mm3
    vol = geo.get("volume", 0)
    expected_vol = 5152.2
    tolerance = 0.05  # 5%
    
    if abs(vol - expected_vol) / expected_vol < tolerance:
        score += 20
        feedback.append("Volume correct.")
    elif abs(vol - expected_vol) / expected_vol < 0.15:
        score += 10
        feedback.append("Volume roughly correct.")
    else:
        feedback.append(f"Volume incorrect ({vol:.1f} vs {expected_vol:.1f}).")

    # Check 6: Cross-sections (20 pts)
    sections = geo.get("sections", {})
    sec_score = 0
    
    # Sec 1: 8mm
    if abs(sections.get("section_1", 0) - 8.0) < 0.5:
        sec_score += 7
    # Sec 2: 12mm
    if abs(sections.get("section_2", 0) - 12.0) < 0.5:
        sec_score += 7
    # Sec 3: 10mm
    if abs(sections.get("section_3", 0) - 10.0) < 0.5:
        sec_score += 6
        
    score += sec_score
    if sec_score == 20:
        feedback.append("All diameters correct.")
    elif sec_score > 0:
        feedback.append("Some diameters incorrect.")
    else:
        feedback.append("Diameters incorrect.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback),
        "details": geo
    }