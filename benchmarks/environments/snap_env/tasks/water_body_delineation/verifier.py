#!/usr/bin/env python3
"""Verifier for water_body_delineation task.

Scoring breakdown (must sum to exactly 100):
  Product saved in DIMAP format:              10 pts
  NDWI band (Green-NIR normalized diff):      20 pts
  MNDWI band (Green-SWIR normalized diff):    20 pts
  Water mask (binary threshold classification):15 pts
  Water confidence layer (multi-index combo):  15 pts
  GeoTIFF exported with non-trivial size:     20 pts
                                       TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import tempfile


def verify_water_body_delineation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/water_body_delineation_result.json', result_path)
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

    # Criterion 2: NDWI band (20 pts)
    # NDWI = (Green - NIR) / (Green + NIR) = (band_4 - band_2) / (band_4 + band_2)
    ndwi_expr = result.get('ndwi_expression', '')
    if result.get('has_ndwi') and ndwi_expr:
        el = ndwi_expr.lower().replace(' ', '')
        has_green = any(kw in el for kw in ['band_4', 'green', 'b4'])
        has_nir = any(kw in el for kw in ['band_2', 'nir', 'b2'])
        has_arith = '/' in el and '-' in el
        if has_green and has_nir and has_arith:
            score += 20
            feedback.append("NDWI with correct Green-NIR expression (+20)")
        else:
            score += 15
            feedback.append("NDWI band with expression (+15)")
    elif result.get('has_ndwi'):
        score += 10
        feedback.append("NDWI band found but no expression (+10)")
    else:
        feedback.append("No NDWI band found (0/20)")

    # Criterion 3: MNDWI band (20 pts)
    # MNDWI = (Green - SWIR) / (Green + SWIR) = (band_4 - band_1) / (band_4 + band_1)
    mndwi_expr = result.get('mndwi_expression', '')
    if result.get('has_mndwi') and mndwi_expr:
        el = mndwi_expr.lower().replace(' ', '')
        has_green = any(kw in el for kw in ['band_4', 'green', 'b4'])
        has_swir = any(kw in el for kw in ['band_1', 'swir', 'b1'])
        has_arith = '/' in el and '-' in el
        if has_green and has_swir and has_arith:
            score += 20
            feedback.append("MNDWI with correct Green-SWIR expression (+20)")
        else:
            score += 15
            feedback.append("MNDWI band with expression (+15)")
    elif result.get('has_mndwi'):
        score += 10
        feedback.append("MNDWI band found but no expression (+10)")
    else:
        # Partial credit if they created a second water index by any name
        vbands = result.get('virtual_bands', {})
        water_exprs = [e for e in vbands.values()
                       if 'band_1' in e.lower() and 'band_4' in e.lower() and '/' in e]
        if water_exprs:
            score += 12
            feedback.append("Second water index found via expression (+12)")
        else:
            feedback.append("No MNDWI/second water index found (0/20)")

    # Criterion 4: Water mask with threshold (15 pts)
    mask_expr = result.get('water_mask_expression', '')
    if result.get('has_water_mask') and mask_expr:
        el = mask_expr.lower().replace(' ', '')
        has_cond = 'if(' in el or '?' in el or '>' in el or '<' in el
        if has_cond:
            score += 15
            feedback.append("Water mask with threshold logic (+15)")
        else:
            score += 10
            feedback.append("Water mask band with expression (+10)")
    elif result.get('has_water_mask'):
        score += 8
        feedback.append("Water mask band exists (+8)")
    else:
        # Fallback: check any virtual band for threshold on water index
        vbands = result.get('virtual_bands', {})
        has_threshold = any(
            ('if(' in e.lower().replace(' ', '') or '>' in e or '<' in e) and
            any(kw in e.lower() for kw in ['ndwi', 'mndwi', 'water', 'band_4'])
            for e in vbands.values()
        )
        if has_threshold:
            score += 10
            feedback.append("Threshold expression found in unnamed band (+10)")
        else:
            feedback.append("No water mask found (0/15)")

    # Criterion 5: Water confidence layer combining indices (15 pts)
    conf_expr = result.get('water_confidence_expression', '')
    if result.get('has_water_confidence') and conf_expr:
        el = conf_expr.lower().replace(' ', '')
        refs_multiple = sum(1 for kw in ['ndwi', 'mndwi', 'water', 'mask']
                            if kw in el)
        if refs_multiple >= 2:
            score += 15
            feedback.append("Water confidence combining multiple indices (+15)")
        else:
            score += 10
            feedback.append("Water confidence layer found (+10)")
    elif result.get('has_water_confidence'):
        score += 8
        feedback.append("Water confidence band exists (+8)")
    else:
        # Check total virtual bands count as proxy for combined analysis
        vbands = result.get('virtual_bands', {})
        if len(vbands) >= 4:
            score += 5
            feedback.append("Multiple virtual bands suggest combined analysis (+5)")
        else:
            feedback.append("No water confidence layer found (0/15)")

    # Criterion 6: GeoTIFF exported with non-trivial size (20 pts)
    tif_size = result.get('tif_file_size', 0)
    if result.get('tif_found') and result.get('tif_created_after_start') and tif_size > 1024:
        score += 20
        feedback.append(f"GeoTIFF exported ({tif_size} bytes) (+20)")
    elif result.get('tif_found') and result.get('tif_created_after_start'):
        score += 12
        feedback.append(f"GeoTIFF exported but small ({tif_size} bytes) (+12)")
    elif result.get('tif_found'):
        score += 5
        feedback.append("GeoTIFF found but timestamp unclear (+5)")
    else:
        feedback.append("No GeoTIFF export found (0/20)")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": "; ".join(feedback)}
