#!/usr/bin/env python3
"""
Verifier for Euclidean Spectral Target Detection task.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_euclidean_spectral_target_detection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/export_result.json', result_path)
        with open(result_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # 1. Product Saved (10 pts)
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 10
        feedback.append("Product saved in DIMAP format (+10)")
    elif result.get('dim_found'):
        score += 5
        feedback.append("Product found but timestamp unclear (+5)")
    else:
        feedback.append("No saved DIMAP product found (0/10)")

    # 2. Export Executed (10 pts)
    if result.get('tif_found') and result.get('tif_created_after_start'):
        if result.get('tif_size') > 100000:
            score += 10
            feedback.append("GeoTIFF exported with valid size (+10)")
        else:
            score += 5
            feedback.append("GeoTIFF exported but size is suspiciously small (+5)")
    else:
        feedback.append("No GeoTIFF export found (0/10)")

    # 3. Distance Band Created (15 pts)
    if result.get('spectral_distance_found'):
        score += 15
        feedback.append("Distance band 'spectral_distance' found (+15)")
    else:
        feedback.append("Distance band 'spectral_distance' not found (0/15)")

    # 4. Distance Expression Valid (25 pts)
    dist_expr = result.get('spectral_distance_expr', '').lower().replace(' ', '')
    if dist_expr:
        has_vals = all(val in dist_expr for val in ['180', '130', '100', '85'])
        has_bands = all(b in dist_expr for b in ['band_1', 'band_2', 'band_3', 'band_4']) or \
                    all(b in dist_expr for b in ['band1', 'band2', 'band3', 'band4'])
        has_math = any(op in dist_expr for op in ['+', '-', '*', '/', 'pow', '^', 'sq'])
        
        if has_vals and has_bands and has_math:
            score += 25
            feedback.append("Distance expression is valid (+25)")
        elif has_vals and has_bands:
            score += 15
            feedback.append("Distance expression has correct bands and values but math operators missing (+15)")
        elif has_bands:
            score += 10
            feedback.append("Distance expression references bands but missing values (+10)")
        else:
            score += 5
            feedback.append("Distance expression exists but is incorrect (+5)")
    else:
        feedback.append("No distance expression found (0/25)")

    # 5. Mask Band Created (15 pts)
    if result.get('target_outcrop_found'):
        score += 15
        feedback.append("Mask band 'target_outcrop' found (+15)")
    else:
        feedback.append("Mask band 'target_outcrop' not found (0/15)")

    # 6. Mask Expression Valid (15 pts)
    mask_expr = result.get('target_outcrop_expr', '').lower().replace(' ', '')
    if mask_expr:
        has_lt25 = '<25' in mask_expr or '25>' in mask_expr
        has_ref = 'spectral_distance' in mask_expr or 'spectraldistance' in mask_expr or '180' in mask_expr
        
        if has_lt25 and has_ref:
            score += 15
            feedback.append("Mask expression is valid (+15)")
        elif has_lt25:
            score += 10
            feedback.append("Mask expression has correct threshold but reference unclear (+10)")
        else:
            score += 5
            feedback.append("Mask expression exists but is incorrect (+5)")
    else:
        feedback.append("No mask expression found (0/15)")

    # 7. Raster Value Integrity (10 pts)
    if result.get('tif_size') > 100000 and score >= 90:
        score += 10
        feedback.append("Raster values likely valid based on expressions and file size (+10)")
    else:
        feedback.append("Raster value integrity cannot be fully confirmed (0/10)")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}