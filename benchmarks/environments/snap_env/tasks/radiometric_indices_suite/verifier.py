#!/usr/bin/env python3
"""Verifier for radiometric_indices_suite task.

Scoring breakdown (must sum to exactly 100):
  Product saved in DIMAP format:              10 pts
  NDVI band with valid expression:            15 pts
  NDWI band with valid expression:            15 pts
  SAVI band with valid expression:            15 pts
  Fourth+ index band (BSI or other):          10 pts
  Classification band with multi-criteria:    20 pts
  GeoTIFF exported with non-trivial size:     15 pts
                                       TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import tempfile


def _validate_normalized_difference(expr, band_a_kws, band_b_kws):
    """Check if an expression looks like a normalized difference using expected bands."""
    if not expr:
        return False
    el = expr.lower().replace(' ', '')
    has_a = any(kw in el for kw in band_a_kws)
    has_b = any(kw in el for kw in band_b_kws)
    has_arith = '/' in el and ('-' in el or '+' in el)
    return has_a and has_b and has_arith


def verify_radiometric_indices_suite(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/radiometric_indices_suite_result.json', result_path)
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
        feedback.append("Product saved (+10)")
    elif result.get('dim_found'):
        score += 7
        feedback.append("Product found but timestamp unclear (+7)")
    else:
        feedback.append("No saved product found (0/10)")

    # Criterion 2: NDVI band with valid expression (15 pts)
    # NDVI = (NIR - Red) / (NIR + Red) = (band_2 - band_3) / (band_2 + band_3)
    ndvi_expr = result.get('ndvi_expression', '')
    if result.get('has_ndvi') and _validate_normalized_difference(
            ndvi_expr, ['band_2', 'nir', 'b2'], ['band_3', 'red', 'b3']):
        score += 15
        feedback.append("NDVI band with correct expression (+15)")
    elif result.get('has_ndvi') and ndvi_expr:
        score += 12
        feedback.append("NDVI band found with expression (+12)")
    elif result.get('has_ndvi'):
        score += 8
        feedback.append("NDVI band found but no expression detected (+8)")
    else:
        feedback.append("No NDVI band found (0/15)")

    # Criterion 3: NDWI band with valid expression (15 pts)
    # NDWI = (Green - NIR) / (Green + NIR) = (band_4 - band_2) / (band_4 + band_2)
    ndwi_expr = result.get('ndwi_expression', '')
    if result.get('has_ndwi') and _validate_normalized_difference(
            ndwi_expr, ['band_4', 'green', 'b4'], ['band_2', 'nir', 'b2']):
        score += 15
        feedback.append("NDWI band with correct expression (+15)")
    elif result.get('has_ndwi') and ndwi_expr:
        score += 12
        feedback.append("NDWI band found with expression (+12)")
    elif result.get('has_ndwi'):
        score += 8
        feedback.append("NDWI band found but no expression detected (+8)")
    else:
        feedback.append("No NDWI band found (0/15)")

    # Criterion 4: SAVI band with valid expression (15 pts)
    # SAVI = ((NIR - Red) / (NIR + Red + L)) * (1 + L) where L=0.5
    savi_expr = result.get('savi_expression', '')
    if result.get('has_savi') and savi_expr:
        el = savi_expr.lower().replace(' ', '')
        has_bands = ('band_2' in el or 'nir' in el) and ('band_3' in el or 'red' in el)
        has_L = '0.5' in el or '1.5' in el or '+l' in el
        if has_bands and has_L:
            score += 15
            feedback.append("SAVI band with L-factor expression (+15)")
        elif has_bands:
            score += 12
            feedback.append("SAVI band with band references (+12)")
        else:
            score += 8
            feedback.append("SAVI band found with expression (+8)")
    elif result.get('has_savi'):
        score += 8
        feedback.append("SAVI band found but no expression detected (+8)")
    else:
        feedback.append("No SAVI band found (0/15)")

    # Criterion 5: Fourth+ index band - BSI or additional (10 pts)
    # BSI = ((SWIR+Red)-(NIR+Green))/((SWIR+Red)+(NIR+Green))
    has_fourth = result.get('has_bsi') or result.get('additional_index_count', 0) > 0
    vbands = result.get('virtual_bands', {})
    total_index_count = sum([
        1 if result.get('has_ndvi') else 0,
        1 if result.get('has_ndwi') else 0,
        1 if result.get('has_savi') else 0,
        1 if result.get('has_bsi') else 0,
        result.get('additional_index_count', 0)
    ])
    if has_fourth and total_index_count >= 4:
        score += 10
        feedback.append(f"4+ spectral indices found ({total_index_count}) (+10)")
    elif has_fourth:
        score += 7
        feedback.append(f"Additional index band found ({total_index_count} total) (+7)")
    elif len(vbands) >= 4:
        score += 5
        feedback.append(f"4+ virtual bands exist ({len(vbands)}) (+5)")
    else:
        feedback.append(f"Insufficient index bands ({total_index_count}) (0/10)")

    # Criterion 6: Classification band with multi-criteria conditional logic (20 pts)
    class_expr = result.get('classification_expression', '')
    if result.get('has_classification_band') and class_expr:
        el = class_expr.lower().replace(' ', '')
        has_cond = any(kw in el for kw in ['if(', 'if (', '?'])
        has_nums = any(c.isdigit() for c in el)
        # Check for nested conditionals (multi-class)
        nested = el.count('if(') + el.count('if (')
        if has_cond and nested >= 2 and has_nums:
            score += 20
            feedback.append("Classification with nested conditionals (+20)")
        elif has_cond and has_nums:
            score += 15
            feedback.append("Classification with conditional thresholds (+15)")
        elif has_cond:
            score += 10
            feedback.append("Classification with basic conditional (+10)")
        else:
            score += 8
            feedback.append("Classification band with expression (+8)")
    elif result.get('has_classification_band'):
        score += 8
        feedback.append("Classification band exists but no expression (+8)")
    else:
        # Fallback: check any virtual band for conditional expressions
        has_conditional = any(
            'if(' in expr.lower().replace(' ', '') or '?' in expr
            for expr in vbands.values()
        )
        if has_conditional:
            score += 8
            feedback.append("Conditional expression found in unnamed band (+8)")
        else:
            feedback.append("No classification band found (0/20)")

    # Criterion 7: GeoTIFF exported with non-trivial size (15 pts)
    tif_size = result.get('tif_file_size', 0)
    if result.get('tif_found') and result.get('tif_created_after_start') and tif_size > 1024:
        score += 15
        feedback.append(f"GeoTIFF exported ({tif_size} bytes) (+15)")
    elif result.get('tif_found') and result.get('tif_created_after_start'):
        score += 10
        feedback.append(f"GeoTIFF exported but small ({tif_size} bytes) (+10)")
    elif result.get('tif_found'):
        score += 5
        feedback.append("GeoTIFF found but timestamp unclear (+5)")
    else:
        feedback.append("No GeoTIFF export found (0/15)")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": "; ".join(feedback)}
