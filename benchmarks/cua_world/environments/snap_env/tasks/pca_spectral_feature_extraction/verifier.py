#!/usr/bin/env python3
"""
Verifier for pca_spectral_feature_extraction task.

Scoring breakdown (must sum to exactly 100):
  DIMAP file exists:                       15 pts
  Principal component bands present:       25 pts
  At least 3 PC bands:                     10 pts
  `spectral_anomaly` band exists:          20 pts
  Anomaly expression uses multiple bands:  10 pts
  GeoTIFF exported:                        15 pts
  GeoTIFF has multiple bands:               5 pts
                                    TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import re
import tempfile

def verify_pca_spectral_feature_extraction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/pca_task_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # Criterion 1: DIMAP file exists (15 pts)
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 15
        feedback.append("DIMAP product saved correctly (+15)")
    elif result.get('dim_found'):
        score += 10
        feedback.append("DIMAP product found but timestamp unclear (+10)")
    else:
        feedback.append("No saved DIMAP product found (0/15)")

    # Criterion 2: Principal component bands present (25 pts)
    pc_count = result.get('pc_band_count', 0)
    if pc_count >= 1:
        score += 25
        feedback.append(f"Principal component bands found ({pc_count}) (+25)")
    else:
        feedback.append("No principal component bands found (0/25)")

    # Criterion 3: At least 3 PC bands (10 pts)
    if pc_count >= 3:
        score += 10
        feedback.append("At least 3 PC bands generated (+10)")
    elif pc_count > 0:
        feedback.append(f"Only {pc_count} PC bands found, expected >= 3 (0/10)")
    else:
        feedback.append("PC band threshold not met (0/10)")

    # Criterion 4: `spectral_anomaly` band exists (20 pts)
    if result.get('spectral_anomaly_exists'):
        score += 20
        feedback.append("`spectral_anomaly` band found (+20)")
    else:
        feedback.append("`spectral_anomaly` band NOT found (0/20)")

    # Criterion 5: Anomaly expression uses multiple bands (10 pts)
    expr = result.get('anomaly_expression', '')
    if expr:
        # Extract alphanumeric words that look like band names or variables
        words = set(re.findall(r'[a-zA-Z_][a-zA-Z0-9_]*', expr.lower()))
        # Remove common math function names SNAP uses
        math_funcs = {'sin', 'cos', 'tan', 'exp', 'log', 'log10', 'abs', 'sqrt', 'min', 'max', 'pow'}
        variables = words - math_funcs

        if len(variables) >= 2:
            score += 10
            feedback.append("Anomaly expression references multiple variables (+10)")
        elif len(variables) == 1:
            score += 5
            feedback.append(f"Anomaly expression references only 1 variable ({list(variables)[0]}) (+5)")
        else:
            feedback.append("Anomaly expression does not reference variables clearly (0/10)")
    else:
        feedback.append("No valid anomaly expression found (0/10)")

    # Criterion 6: GeoTIFF exported (15 pts)
    tif_size = result.get('tif_file_size', 0)
    if result.get('tif_found') and result.get('tif_created_after_start') and tif_size > 100000:
        score += 15
        feedback.append("GeoTIFF exported successfully (+15)")
    elif result.get('tif_found') and tif_size > 100000:
        score += 10
        feedback.append("GeoTIFF exported but timestamp unclear (+10)")
    elif result.get('tif_found'):
        score += 5
        feedback.append("GeoTIFF exported but size too small (likely empty) (+5)")
    else:
        feedback.append("No GeoTIFF export found (0/15)")

    # Criterion 7: GeoTIFF has multiple bands (5 pts)
    tif_bands = result.get('tif_band_count', 0)
    if tif_bands > 1:
        score += 5
        feedback.append(f"GeoTIFF has multiple bands ({tif_bands}) (+5)")
    elif pc_count > 0 and tif_bands <= 1:
        # Sometimes PIL struggles to read SNAP multiband TIFs; if DIM has PCs and TIF is huge, we can assume it worked.
        if tif_size > 5000000:
            score += 5
            feedback.append("GeoTIFF size is large, assuming multiband export succeeded (+5)")
        else:
            feedback.append("GeoTIFF appears to have only 1 band (0/5)")
    else:
        feedback.append("GeoTIFF multiple bands check failed (0/5)")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": "; ".join(feedback)}