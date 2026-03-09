#!/usr/bin/env python3
"""Verifier for terrain_slope_analysis task.

Scoring breakdown (must sum to exactly 100):
  Product saved in DIMAP format:              15 pts
  Slope/gradient band exists:                 25 pts
  Classification band with conditional logic: 25 pts
  Additional derived bands beyond original:   10 pts
  GeoTIFF exported:                           15 pts
  GeoTIFF has non-trivial size:               10 pts
                                       TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import tempfile


def verify_terrain_slope_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/terrain_slope_analysis_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # Criterion 1: Product saved in DIMAP format (15 pts)
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 15
        feedback.append("Product saved (+15)")
    elif result.get('dim_found'):
        score += 10
        feedback.append("Product found but timestamp unclear (+10)")
    else:
        feedback.append("No saved product found (0/15)")

    # Criterion 2: Slope/gradient band exists (25 pts)
    if result.get('has_slope_band'):
        score += 25
        feedback.append("Slope/gradient band found (+25)")
    else:
        # Fallback: check if any virtual band expression references elevation/band_1
        vbands = result.get('virtual_bands', {})
        has_deriv = any(
            'band_1' in expr.lower() or 'band1' in expr.lower()
            for expr in vbands.values()
        )
        if has_deriv and len(vbands) >= 1:
            score += 15
            feedback.append("Derived band from elevation data found (+15)")
        else:
            feedback.append("No slope/gradient band found (0/25)")

    # Criterion 3: Classification band with conditional logic (25 pts)
    class_expr = result.get('classification_expression', '')
    if result.get('has_classification_band') and class_expr:
        el = class_expr.lower().replace(' ', '')
        has_cond = any(kw in el for kw in ['if(', 'if (', '?', '<', '>'])
        has_nums = any(c.isdigit() for c in el)
        if has_cond and has_nums:
            score += 25
            feedback.append("Classification band with conditional thresholds (+25)")
        elif has_cond or has_nums:
            score += 15
            feedback.append("Classification band with partial logic (+15)")
        else:
            score += 10
            feedback.append("Classification band exists but no conditional logic (+10)")
    elif result.get('has_classification_band'):
        score += 10
        feedback.append("Classification band exists but no expression detected (+10)")
    else:
        # Check any virtual band for conditional expressions
        vbands = result.get('virtual_bands', {})
        has_conditional = any(
            'if(' in expr.lower().replace(' ', '') or '?' in expr
            for expr in vbands.values()
        )
        if has_conditional:
            score += 10
            feedback.append("Conditional expression found in unnamed band (+10)")
        else:
            feedback.append("No classification band found (0/25)")

    # Criterion 4: Additional derived bands beyond original DEM (10 pts)
    total_bands = result.get('total_band_count', 0)
    if total_bands >= 3:
        score += 10
        feedback.append(f"Multiple derived bands ({total_bands} total) (+10)")
    elif total_bands >= 2:
        score += 5
        feedback.append(f"One derived band ({total_bands} total) (+5)")
    else:
        feedback.append(f"No additional bands (total={total_bands}) (0/10)")

    # Criterion 5: GeoTIFF exported (15 pts)
    if result.get('tif_found') and result.get('tif_created_after_start'):
        score += 15
        feedback.append("GeoTIFF exported (+15)")
    else:
        feedback.append("No GeoTIFF export found (0/15)")

    # Criterion 6: GeoTIFF has non-trivial size (10 pts)
    tif_size = result.get('tif_file_size', 0)
    if tif_size > 1024:
        score += 10
        feedback.append(f"GeoTIFF size {tif_size} bytes (+10)")
    elif tif_size > 0:
        score += 5
        feedback.append(f"GeoTIFF small: {tif_size} bytes (+5)")
    else:
        feedback.append("GeoTIFF empty or not found (0/10)")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": "; ".join(feedback)}
