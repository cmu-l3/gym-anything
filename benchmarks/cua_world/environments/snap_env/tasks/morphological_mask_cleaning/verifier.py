#!/usr/bin/env python3
"""
Verifier for Morphological Mask Cleaning task.

Checks:
  1. DIMAP Product exists (10 pts)
  2. Bands exist (20 pts)
  3. Binary integrity (15 pts)
  4. Erosion Proof: sum(eroded_mask) < sum(initial_mask) (20 pts)
  5. Dilation Proof: sum(cleaned_mask) > sum(eroded_mask) (20 pts)
  6. GeoTIFF Exported (15 pts)
"""

import json
import os
import tempfile


def verify_morphological_mask_cleaning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available in environment"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/morphological_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse result data: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # Criterion 1: DIMAP Product exists
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 10
        feedback.append("DIMAP product saved (+10)")
    elif result.get('dim_found'):
        score += 5
        feedback.append("DIMAP product found but timestamp indicates it wasn't newly created (+5)")
    else:
        feedback.append("No saved DIMAP product found (0/10)")

    # Criterion 2: Bands exist in .data physical directory
    bands_found = result.get('bands_found', [])
    if len(bands_found) == 3:
        score += 20
        feedback.append("All 3 required bands (initial, eroded, cleaned) found in .data directory (+20)")
    elif len(bands_found) > 0:
        pts = len(bands_found) * 6
        score += pts
        feedback.append(f"Found {len(bands_found)}/3 required bands (+{pts})")
    else:
        feedback.append("Required physical bands missing from .data directory (ensure 'Virtual' was unchecked) (0/20)")

    # Criterion 3: Binary integrity
    if len(bands_found) > 0 and result.get('binary_integrity', False):
        score += 15
        feedback.append("Binary integrity confirmed: masks contain strictly 0 and 1 values (+15)")
    else:
        feedback.append("Binary integrity failed (values other than 0/1 found) or no valid bands to check (0/15)")

    sums = result.get('sums', {})

    # Criterion 4: Erosion Mathematical Proof
    if 'initial_mask' in sums and 'eroded_mask' in sums:
        init_sum = sums['initial_mask']
        erod_sum = sums['eroded_mask']
        if erod_sum < init_sum:
            score += 20
            feedback.append(f"Erosion mathematically proven: {erod_sum} < {init_sum} (+20)")
        else:
            feedback.append(f"Erosion proof failed: {erod_sum} >= {init_sum} (0/20)")
    else:
        feedback.append("Cannot test erosion proof: missing requisite bands (0/20)")

    # Criterion 5: Dilation Mathematical Proof
    if 'eroded_mask' in sums and 'cleaned_mask' in sums:
        erod_sum = sums['eroded_mask']
        clean_sum = sums['cleaned_mask']
        if clean_sum > erod_sum:
            score += 20
            feedback.append(f"Dilation mathematically proven: {clean_sum} > {erod_sum} (+20)")
        else:
            feedback.append(f"Dilation proof failed: {clean_sum} <= {erod_sum} (0/20)")
    else:
        feedback.append("Cannot test dilation proof: missing requisite bands (0/20)")

    # Criterion 6: GeoTIFF Exported
    if result.get('tif_found') and result.get('tif_size', 0) > 1024:
        score += 15
        feedback.append("GeoTIFF exported with non-trivial size (+15)")
    elif result.get('tif_found'):
        score += 5
        feedback.append("GeoTIFF exported but size is very small (+5)")
    else:
        feedback.append("No GeoTIFF export found (0/15)")

    # Pass Condition requires at least 70% and valid overall morphological Opening logic (clean <= initial)
    opening_valid = False
    if 'cleaned_mask' in sums and 'initial_mask' in sums:
        if sums['cleaned_mask'] <= sums['initial_mask']:
            opening_valid = True

    passed = score >= 70 and opening_valid
    if not passed and score >= 70:
        feedback.append("FAIL: Score >= 70, but overarching Opening morphological proof (cleaned <= initial) failed.")

    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}