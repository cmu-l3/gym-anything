#!/usr/bin/env python3
"""Verifier for multisource_spectral_integration task.

Scoring breakdown (must sum to exactly 100):
  Integrated product saved in DIMAP:           15 pts
  Multi-source bands present (both inputs):    25 pts
  Derived spectral index band exists:          20 pts
  Index expression references both bands:      15 pts
  GeoTIFF exported:                            15 pts
  GeoTIFF has non-trivial size:                10 pts
                                        TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import tempfile


def verify_multisource_spectral_integration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/multisource_spectral_integration_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # Criterion 1: Product saved in DIMAP (15 pts)
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 15
        feedback.append("Product saved (+15)")
    elif result.get('dim_found'):
        score += 10
        feedback.append("Product found but timestamp unclear (+10)")
    else:
        feedback.append("No saved product found (0/15)")

    # Criterion 2: Multi-source bands present (25 pts)
    if result.get('has_multisource_bands'):
        score += 25
        feedback.append("Multi-source bands detected (+25)")
    elif result.get('source_band_count', 0) >= 2:
        score += 20
        feedback.append("Multiple source bands found (+20)")
    elif result.get('total_band_count', 0) >= 2:
        score += 10
        feedback.append("Multiple bands found but source unclear (+10)")
    else:
        feedback.append("No multi-source integration detected (0/25)")

    # Criterion 3: Derived spectral index band exists (20 pts)
    if result.get('has_derived_index'):
        score += 20
        feedback.append("Derived spectral index found (+20)")
    else:
        # Check if any virtual bands exist at all
        vbands = result.get('virtual_bands', {})
        if len(vbands) > 0:
            score += 10
            feedback.append("Virtual band found but not recognized as index (+10)")
        else:
            feedback.append("No derived index band found (0/20)")

    # Criterion 4: Index expression references both bands (15 pts)
    expr = result.get('derived_index_expression', '')
    if expr:
        el = expr.lower().replace(' ', '')
        # Check for normalized difference pattern or ratio
        has_division = '/' in el
        has_subtraction = '-' in el
        has_addition = '+' in el
        # Check for two distinct band references
        band_refs = set()
        for token in ['band_1', 'band_2', 'band1', 'band2', 'b04', 'b08',
                       'red', 'nir', '$4', '$8']:
            if token in el:
                band_refs.add(token)
        if len(band_refs) >= 2 and (has_division or has_subtraction):
            score += 15
            feedback.append("Index expression uses both bands correctly (+15)")
        elif len(band_refs) >= 1:
            score += 8
            feedback.append("Index expression references one band (+8)")
        else:
            score += 5
            feedback.append("Index expression found but band refs unclear (+5)")
    else:
        feedback.append("No index expression found (0/15)")

    # Criterion 5: GeoTIFF exported (15 pts)
    if result.get('tif_found') and result.get('tif_created_after_start'):
        score += 15
        feedback.append("GeoTIFF exported (+15)")
    else:
        feedback.append("No GeoTIFF export found (0/15)")

    # Criterion 6: GeoTIFF non-trivial size (10 pts)
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
