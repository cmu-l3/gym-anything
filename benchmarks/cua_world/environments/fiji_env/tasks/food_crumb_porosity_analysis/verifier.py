#!/usr/bin/env python3
"""
Verifier for food_crumb_porosity_analysis task.

Scoring Criteria:
1. Artifact Existence (20pts): CSV, Report, and Mask image created during task.
2. Scale Calibration (30pts): Mean pore area should be in cm² range (0.01-0.5), not pixel range (>10).
3. Porosity Calculation (30pts): Porosity % should be within realistic range (30-60%).
4. Segmentation Check (20pts): CSV contains valid data rows (>10 pores detected).

Total: 100 points. Pass threshold: 70 points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_food_crumb_porosity_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_porosity_min = metadata.get('expected_porosity_min', 30.0)
    expected_porosity_max = metadata.get('expected_porosity_max', 60.0)
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    parsed = result.get("parsed_data", {})
    
    # 1. Artifact Existence (20 pts)
    artifacts_score = 0
    if result.get("csv_created", False): artifacts_score += 5
    if result.get("report_created", False): artifacts_score += 10
    if result.get("mask_created", False): artifacts_score += 5
    
    score += artifacts_score
    feedback.append(f"Artifacts created: {artifacts_score}/20")
    
    # 2. Scale Calibration (30 pts)
    # If the user didn't set scale, area will be in pixels (likely > 100 for a pore)
    # If set to cm, area should be small (e.g. 0.01 - 0.5 cm²)
    mean_area = parsed.get("mean_area", 0.0)
    
    scale_score = 0
    if 0.001 <= mean_area <= 1.5:
        scale_score = 30
        feedback.append(f"Scale calibration looks correct (Mean Area: {mean_area:.4f}).")
    elif mean_area > 10:
        feedback.append(f"Scale likely incorrect/pixels (Mean Area: {mean_area:.1f}).")
    else:
        feedback.append(f"Mean area value suspicious or zero ({mean_area}).")
    
    score += scale_score
    feedback.append(f"Scale check: {scale_score}/30")
    
    # 3. Porosity Calculation (30 pts)
    # Check the reported porosity from text file
    reported_porosity = parsed.get("report_porosity", -1.0)
    
    porosity_score = 0
    if expected_porosity_min <= reported_porosity <= expected_porosity_max:
        porosity_score = 30
        feedback.append(f"Porosity {reported_porosity}% is within expected range.")
    elif reported_porosity > 0:
        # Partial credit if calculated but slightly off range
        diff = min(abs(reported_porosity - expected_porosity_min), abs(reported_porosity - expected_porosity_max))
        if diff < 10: 
            porosity_score = 15
            feedback.append(f"Porosity {reported_porosity}% is close to expected range.")
        else:
            feedback.append(f"Porosity {reported_porosity}% is widely off expected range ({expected_porosity_min}-{expected_porosity_max}).")
    else:
        feedback.append("Porosity not found in report or invalid.")
        
    score += porosity_score
    feedback.append(f"Porosity check: {porosity_score}/30")
    
    # 4. Segmentation Check (20 pts)
    # Check if we actually detected particles
    rows = parsed.get("csv_rows", 0)
    seg_score = 0
    if rows >= 10:
        seg_score = 20
        feedback.append(f"Segmentation successful ({rows} pores detected).")
    elif rows > 0:
        seg_score = 10
        feedback.append(f"Segmentation weak (only {rows} pores detected).")
    else:
        feedback.append("No pores detected in CSV.")
        
    score += seg_score
    feedback.append(f"Segmentation check: {seg_score}/20")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }