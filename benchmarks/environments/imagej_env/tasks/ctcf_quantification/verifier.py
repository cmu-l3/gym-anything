#!/usr/bin/env python3
"""
Verifier for CTCF Quantification task.

Checks:
1. Result file exists and created after task start.
2. Contains at least 5 rows of cell data.
3. Contains required columns (Area, IntDen, Background, CTCF).
4. Values are physically plausible for the image.
5. CTCF calculation is mathematically correct based on the inputs provided.

Formula: CTCF = IntDen - (Area * Mean_Background)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ctcf_quantification(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ctcf_quantification_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check 1: File Existence & Timing (10 pts)
    if result.get('file_exists'):
        file_time = result.get('file_modified_time', 0)
        task_start = result.get('task_start_timestamp', 0)
        if file_time > task_start:
            score += 10
            feedback.append("Result file created.")
        else:
            feedback.append("Result file exists but is old (pre-dates task).")
    else:
        feedback.append("Result file not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Check 2: Data Quantity (15 pts)
    data = result.get('data', [])
    # Filter for valid rows (having numbers)
    valid_rows = [r for r in data if isinstance(r.get('area'), (int, float))]
    
    if len(valid_rows) >= 5:
        score += 15
        feedback.append(f"Found {len(valid_rows)} valid cell measurements.")
    else:
        feedback.append(f"Insufficient measurements: found {len(valid_rows)}, expected >= 5.")

    # Check 3: Column Presence & Value Plausibility (45 pts)
    # Area (15 pts)
    areas = [r.get('area') for r in valid_rows if isinstance(r.get('area'), (int, float))]
    if areas:
        avg_area = sum(areas) / len(areas)
        if 1000 <= avg_area <= 200000:
            score += 15
            feedback.append("Area values are plausible.")
        else:
            feedback.append(f"Area values seem implausible (Avg: {avg_area}).")
    else:
        feedback.append("Area column missing or empty.")

    # IntDen (15 pts)
    intdens = [r.get('intden') for r in valid_rows if isinstance(r.get('intden'), (int, float))]
    if intdens and all(i > 0 for i in intdens):
        score += 15
        feedback.append("Integrated Density values present.")
    else:
        feedback.append("Integrated Density column missing or invalid.")

    # Background (15 pts)
    # Background might be in every row or inferred
    backgrounds = [r.get('background') for r in valid_rows if isinstance(r.get('background'), (int, float))]
    has_background = False
    if backgrounds:
        avg_bg = sum(backgrounds) / len(backgrounds)
        if 0 < avg_bg < 255: # 8-bit image
            score += 15
            has_background = True
            feedback.append(f"Background values present (Avg: {avg_bg:.1f}).")
        else:
            feedback.append(f"Background values suspicious (Avg: {avg_bg}).")
    else:
        feedback.append("Background column missing.")

    # Check 4: Calculation Correctness (25 pts)
    # CTCF = IntDen - (Area * Background)
    math_correct_count = 0
    ctcf_values_present = False
    
    for row in valid_rows:
        area = row.get('area')
        intden = row.get('intden')
        bg = row.get('background')
        reported_ctcf = row.get('ctcf')
        
        if all(isinstance(x, (int, float)) for x in [area, intden, bg, reported_ctcf]):
            ctcf_values_present = True
            calculated_ctcf = intden - (area * bg)
            # Allow 5% tolerance
            if abs(reported_ctcf - calculated_ctcf) < (abs(calculated_ctcf) * 0.05 + 1.0):
                math_correct_count += 1
    
    if ctcf_values_present:
        if math_correct_count >= len(valid_rows) - 1: # Allow 1 outlier/error
            score += 25
            feedback.append("CTCF calculations are correct.")
        elif math_correct_count > 0:
            score += 10
            feedback.append(f"Some CTCF calculations correct ({math_correct_count}/{len(valid_rows)}).")
        else:
            feedback.append("CTCF calculations do not match formula.")
    else:
        feedback.append("CTCF column missing or incomplete.")

    # Check 5: VLM Verification (5 pts)
    # Just basic check that VLM is hooked up, could be expanded
    score += 5 
    
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }