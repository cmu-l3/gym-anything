#!/usr/bin/env python3
"""Verifier for elevation_stratified_vegetation_mask task.

Scoring breakdown:
  Collocation Performed (DIMAP XML shows collocation or multiple sources): 20 pts
  NDVI Band Created (valid optical math): 20 pts
  Mask Band Created: 15 pts
  Cross-Domain Expression (AND logic bridging NDVI and elevation): 25 pts
  DIMAP Product Saved: 10 pts
  GeoTIFF Exported: 10 pts
TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import tempfile

def verify_elevation_stratified_vegetation_mask(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/task_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # Criterion 1: DIMAP Product Saved (10 pts)
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 10
        feedback.append("Product saved (+10)")
    elif result.get('dim_found'):
        score += 5
        feedback.append("Product found but timestamp unclear (+5)")
    else:
        feedback.append("No saved product found (0/10)")

    # Criterion 2: Collocation Performed (20 pts)
    collocation_evidence = result.get('collocation_history', False)
    band_names = result.get('band_names', [])
    if collocation_evidence or any('_m' in b.lower() for b in band_names) or any('master' in b.lower() for b in band_names):
        score += 20
        feedback.append("Collocation performed (+20)")
    elif len(band_names) >= 5: # 4 Landsat + 1 DEM
        score += 10
        feedback.append("High band count implies combination (+10)")
    else:
        feedback.append("No clear evidence of collocation (0/20)")

    # Criterion 3: NDVI Band Created (20 pts)
    ndvi_expr = result.get('ndvi_expression', '')
    if result.get('has_ndvi_band'):
        el = ndvi_expr.lower().replace(' ', '')
        if '/' in el and ('-' in el or '+' in el):
            score += 20
            feedback.append("NDVI band created with formula (+20)")
        elif ndvi_expr:
            score += 10
            feedback.append("NDVI band created but formula lacks expected structure (+10)")
        else:
            score += 5
            feedback.append("NDVI band exists but no formula (+5)")
    else:
        feedback.append("No NDVI band found (0/20)")

    # Criterion 4: Mask Band Created (15 pts)
    mask_expr = result.get('mask_expression', '')
    if result.get('has_mask_band'):
        score += 15
        feedback.append("Mask band found (+15)")
    elif mask_expr:
        score += 10
        feedback.append("Mask-like expression found (+10)")
    else:
        feedback.append("No mask band found (0/15)")

    # Criterion 5: Cross-Domain Expression (25 pts)
    if mask_expr:
        el = mask_expr.lower().replace(' ', '')
        has_and = any(kw in el for kw in ['and', '&&', '*'])
        has_gt = '>' in el
        has_nums = any(c.isdigit() for c in el)
        has_ndvi_ref = 'ndvi' in el or ('/' in el and '-' in el)
        has_elev_ref = 'band' in el or 'elev' in el

        if has_and and has_gt and has_nums and has_ndvi_ref:
            score += 25
            feedback.append("Cross-domain conditional mask logic correct (+25)")
        elif has_and and has_gt:
            score += 15
            feedback.append("Mask logic has conditional AND structure (+15)")
        elif has_gt or has_and:
            score += 10
            feedback.append("Mask logic has partial conditional structure (+10)")
        else:
            feedback.append("Mask lacks cross-domain conditional logic (0/25)")
    else:
        feedback.append("No mask expression to evaluate (0/25)")

    # Criterion 6: GeoTIFF Exported (10 pts)
    tif_size = result.get('tif_file_size', 0)
    if result.get('tif_found') and result.get('tif_created_after_start') and tif_size > 100:
        score += 10
        feedback.append("GeoTIFF mask exported (+10)")
    elif result.get('tif_found') and tif_size > 0:
        score += 5
        feedback.append("GeoTIFF exported but timestamp/size unclear (+5)")
    else:
        feedback.append("No valid GeoTIFF export found (0/10)")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": "; ".join(feedback)}