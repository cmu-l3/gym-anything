#!/usr/bin/env python3
"""Verifier for urban_land_analysis task.

Scoring breakdown (must sum to exactly 100):
  Product saved in DIMAP format:              10 pts
  Built-up index (NDBI) band:                 20 pts
  Vegetation index (NDVI) band:               15 pts
  Urban-vegetation differential layer:        15 pts
  Multi-class zoning with conditionals:       25 pts
  GeoTIFF exported with non-trivial size:     15 pts
                                       TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import tempfile


def verify_urban_land_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/urban_land_analysis_result.json', result_path)
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

    # Criterion 2: Built-up index (NDBI) band (20 pts)
    # NDBI = (SWIR - NIR) / (SWIR + NIR) = (band_1 - band_2) / (band_1 + band_2)
    ndbi_expr = result.get('ndbi_expression', '')
    if result.get('has_ndbi') and ndbi_expr:
        el = ndbi_expr.lower().replace(' ', '')
        has_swir = any(kw in el for kw in ['band_1', 'swir', 'b1'])
        has_nir = any(kw in el for kw in ['band_2', 'nir', 'b2'])
        has_arith = '/' in el and '-' in el
        if has_swir and has_nir and has_arith:
            score += 20
            feedback.append("NDBI with correct SWIR-NIR expression (+20)")
        else:
            score += 15
            feedback.append("NDBI band with expression (+15)")
    elif result.get('has_ndbi'):
        score += 10
        feedback.append("NDBI band found but no expression (+10)")
    else:
        feedback.append("No built-up index band found (0/20)")

    # Criterion 3: Vegetation index (NDVI) band (15 pts)
    # NDVI = (NIR - Red) / (NIR + Red) = (band_2 - band_3) / (band_2 + band_3)
    ndvi_expr = result.get('ndvi_expression', '')
    if result.get('has_ndvi') and ndvi_expr:
        el = ndvi_expr.lower().replace(' ', '')
        has_nir = any(kw in el for kw in ['band_2', 'nir', 'b2'])
        has_red = any(kw in el for kw in ['band_3', 'red', 'b3'])
        has_arith = '/' in el and '-' in el
        if has_nir and has_red and has_arith:
            score += 15
            feedback.append("NDVI with correct NIR-Red expression (+15)")
        else:
            score += 12
            feedback.append("NDVI band with expression (+12)")
    elif result.get('has_ndvi'):
        score += 8
        feedback.append("NDVI band found but no expression (+8)")
    else:
        feedback.append("No vegetation index band found (0/15)")

    # Criterion 4: Urban-vegetation differential layer (15 pts)
    diff_expr = result.get('urban_diff_expression', '')
    if result.get('has_urban_diff') and diff_expr:
        el = diff_expr.lower().replace(' ', '')
        refs = sum(1 for kw in ['ndbi', 'ndvi', 'built', 'veg', 'urban']
                   if kw in el)
        if refs >= 2 and '-' in el:
            score += 15
            feedback.append("Urban-vegetation differential with index refs (+15)")
        else:
            score += 10
            feedback.append("Differential layer with expression (+10)")
    elif result.get('has_urban_diff'):
        score += 8
        feedback.append("Differential layer exists (+8)")
    else:
        # Fallback: check if any band subtracts two indices
        vbands = result.get('virtual_bands', {})
        has_diff = any(
            '-' in e and sum(1 for kw in ['ndbi', 'ndvi', 'band_1', 'band_2']
                             if kw in e.lower()) >= 2
            for e in vbands.values()
        )
        if has_diff:
            score += 8
            feedback.append("Subtraction expression found between bands (+8)")
        else:
            feedback.append("No urban-vegetation differential found (0/15)")

    # Criterion 5: Multi-class zoning with conditionals (25 pts)
    zone_expr = result.get('zoning_expression', '')
    if result.get('has_zoning') and zone_expr:
        el = zone_expr.lower().replace(' ', '')
        has_cond = any(kw in el for kw in ['if(', 'if (', '?'])
        nested = el.count('if(') + el.count('if (')
        has_nums = any(c.isdigit() for c in el)
        if has_cond and nested >= 2 and has_nums:
            score += 25
            feedback.append("Multi-class zoning with nested conditionals (+25)")
        elif has_cond and has_nums:
            score += 18
            feedback.append("Zoning with conditional thresholds (+18)")
        elif has_cond:
            score += 12
            feedback.append("Zoning with basic conditional (+12)")
        else:
            score += 8
            feedback.append("Zoning band with expression (+8)")
    elif result.get('has_zoning'):
        score += 8
        feedback.append("Zoning band exists but no expression (+8)")
    else:
        vbands = result.get('virtual_bands', {})
        has_conditional = any(
            'if(' in e.lower().replace(' ', '') or '?' in e
            for e in vbands.values()
        )
        if has_conditional:
            score += 8
            feedback.append("Conditional expression found in unnamed band (+8)")
        else:
            feedback.append("No zoning classification found (0/25)")

    # Criterion 6: GeoTIFF exported with non-trivial size (15 pts)
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
