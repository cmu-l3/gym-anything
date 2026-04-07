#!/usr/bin/env python3
"""
Verifier for spectral_variability_mapping task.
Evaluates both the generated BEAM-DIMAP project (checking band math expressions)
and the GeoTIFF export.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spectral_variability_mapping(traj, env_info, task_info):
    """
    Verify the output of the spectral variability mapping task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    # Copy the exported result JSON from the container
    result_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env('/tmp/task_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result from container: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # Criterion 1: Product saved in DIMAP format (15 pts)
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 15
        feedback.append("DIMAP product saved (+15)")
    elif result.get('dim_found'):
        score += 10
        feedback.append("DIMAP product found but predates task (+10)")
    else:
        feedback.append("No saved DIMAP product found (0/15)")

    bands = result.get('bands', {})

    def check_band(exact_name, keywords_in_expr):
        """Helper to check if a band exists and has an appropriate expression."""
        for bname, bdata in bands.items():
            if bname.lower() == exact_name.lower():
                expr = bdata.get('expression', '').lower()
                matches = sum(1 for kw in keywords_in_expr if kw in expr)
                if matches == len(keywords_in_expr):
                    return 20, f"'{exact_name}' band found with correct expression logic (+20)"
                elif matches > 0:
                    return 15, f"'{exact_name}' band found with partial expression logic (+15)"
                else:
                    return 10, f"'{exact_name}' band found but expression missing or incorrect (+10)"
        return 0, f"'{exact_name}' band not found (0/20)"

    # Criterion 2: spectral_mean band exists (20 pts)
    pts, msg = check_band('spectral_mean', ['band_1', 'band_2', 'band_3', 'band_4', '+'])
    if pts == 0:
        # Fallback check if they just used slightly different logic (e.g. fewer bands)
        pts, msg = check_band('spectral_mean', ['band_', '+', '/'])
    score += pts
    feedback.append(msg)

    # Criterion 3: spectral_range band exists (20 pts)
    pts, msg = check_band('spectral_range', ['max', 'min', 'band_'])
    score += pts
    feedback.append(msg)

    # Criterion 4: nir_deviation band exists (20 pts)
    pts, msg = check_band('nir_deviation', ['band_2', '-'])
    if pts == 20:
        # Extra verification that it references the mean or a reasonable proxy
        nir_bname = next((b for b in bands if b.lower() == 'nir_deviation'), None)
        if nir_bname:
            expr = bands[nir_bname].get('expression', '').lower()
            if 'spectral_mean' not in expr and 'band_1' not in expr:
                # Deduct slight points if neither mean nor expanded mean logic is present
                pts = 15
                msg = "'nir_deviation' band found, but expression may not correctly reference the mean (+15)"
                score -= 5
                feedback[-1] = msg # update prior message
    score += pts
    if pts != 20 or 'nir_deviation' not in " ".join(feedback): # prevent duplicates if updated
        feedback.append(msg)

    # Criterion 5: GeoTIFF exported (15 pts)
    if result.get('tif_found') and result.get('tif_created_after_start'):
        score += 15
        feedback.append(f"GeoTIFF exported (+15)")
    elif result.get('tif_found'):
        score += 8
        feedback.append(f"GeoTIFF found but predates task (+8)")
    else:
        feedback.append("No GeoTIFF export found (0/15)")

    # Criterion 6: GeoTIFF has non-trivial size (10 pts)
    tif_size = result.get('tif_file_size', 0)
    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_geotiff_size', 51200) # 50 KB

    if tif_size >= min_size:
        score += 10
        feedback.append(f"GeoTIFF size is {tif_size/1024:.1f} KB (valid data size) (+10)")
    elif tif_size > 0:
        score += 5
        feedback.append(f"GeoTIFF size is {tif_size/1024:.1f} KB (unusually small) (+5)")
    else:
        feedback.append("GeoTIFF empty or not found (0/10)")

    # Threshold is 70 points
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }