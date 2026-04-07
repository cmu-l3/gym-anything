#!/usr/bin/env python3
"""
Verifier for dark_object_subtraction_correction task.

Scoring breakdown (must sum to exactly 100):
  Product saved in DIMAP format:     10 pts
  GeoTIFF exported:                  10 pts
  Corrected bands present:           20 pts
  Subtraction logic (Band - Const):  20 pts
  Empirical parameter accuracy (>0): 25 pts
  Zero-clamping logic implemented:   15 pts
                              TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_dos_correction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/dos_correction_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # Criterion 1: Product saved in DIMAP format (10 pts)
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 10
        feedback.append("Product saved in DIMAP (+10)")
    elif result.get('dim_found'):
        score += 5
        feedback.append("Product found but timestamp unclear (+5)")
    else:
        feedback.append("No saved DIMAP product found (0/10)")

    # Criterion 2: GeoTIFF exported (10 pts)
    if result.get('tif_found') and result.get('tif_created_after_start'):
        tif_size = result.get('tif_file_size', 0)
        if tif_size > 1024:
            score += 10
            feedback.append(f"GeoTIFF exported [{tif_size} bytes] (+10)")
        else:
            score += 5
            feedback.append("GeoTIFF exported but size is very small (+5)")
    else:
        feedback.append("No GeoTIFF export found (0/10)")

    # Retrieve expressions
    red_expr = result.get('red_expression', '')
    green_expr = result.get('green_expression', '')
    
    # Criterion 3: Corrected bands present (20 pts)
    bands_present = 0
    if result.get('has_red_corrected') and red_expr:
        bands_present += 10
    if result.get('has_green_corrected') and green_expr:
        bands_present += 10
        
    if bands_present > 0:
        score += bands_present
        feedback.append(f"Corrected band definitions found (+{bands_present})")
    else:
        feedback.append("No atmospherically corrected bands found (0/20)")

    # Helper function to analyze expression strings
    def analyze_expression(expr):
        el = expr.lower()
        # Look for minus sign followed by a number
        has_sub = bool(re.search(r'-\s*\d+\.?\d*', el))
        
        # Look for clamping logic (max, if, ternary ?, or >)
        has_clamp = bool(re.search(r'max\s*\(|if\s+|\?|>', el))
        
        # Extract subtracted constant if possible to verify > 0
        match = re.search(r'-\s*(\d+\.?\d*)', el)
        constant = float(match.group(1)) if match else 0.0
        
        valid_constant = constant > 0
        
        return has_sub, has_clamp, valid_constant

    red_sub, red_clamp, red_valid = analyze_expression(red_expr) if red_expr else (False, False, False)
    green_sub, green_clamp, green_valid = analyze_expression(green_expr) if green_expr else (False, False, False)

    # Criterion 4: Subtraction logic (20 pts)
    if red_sub and green_sub:
        score += 20
        feedback.append("Subtraction logic applied to both bands (+20)")
    elif red_sub or green_sub:
        score += 10
        feedback.append("Subtraction logic applied to one band (+10)")
    else:
        feedback.append("No subtraction logic found in expressions (0/20)")

    # Criterion 5: Empirical parameter accuracy (25 pts)
    # We verify that they extracted a positive non-zero constant to subtract
    if red_valid and green_valid:
        score += 25
        feedback.append("Valid empirical path radiance constants subtracted (+25)")
    elif red_valid or green_valid:
        score += 12.5
        feedback.append("Valid empirical constant subtracted for one band (+12.5)")
    else:
        feedback.append("No valid positive constant extracted from data (0/25)")

    # Criterion 6: Zero-clamping logic implemented (15 pts)
    if red_clamp and green_clamp:
        score += 15
        feedback.append("Zero-clamping logic implemented for both bands (+15)")
    elif red_clamp or green_clamp:
        score += 7.5
        feedback.append("Zero-clamping logic implemented for one band (+7.5)")
    else:
        feedback.append("No zero-clamping logic found (0/15)")

    # Determine final success
    passed = score >= 70 and (red_valid or green_valid)

    if not (red_valid or green_valid):
        feedback.append("CRITICAL FAILURE: Did not subtract a valid data-derived constant.")

    return {
        "passed": bool(passed),
        "score": float(score),
        "feedback": " | ".join(feedback),
        "details": result
    }