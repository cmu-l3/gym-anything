#!/usr/bin/env python3
"""Verifier for spatial_feature_enhancement task.

Scoring breakdown (must sum to exactly 100):
  Product saved in DIMAP format:              15 pts
  Filtered band(s) exist beyond originals:    25 pts
  Filter type identifiable by band name:      15 pts
  Original bands preserved alongside filter:  20 pts
  GeoTIFF exported:                           15 pts
  GeoTIFF has non-trivial size:               10 pts
                                       TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import tempfile


def verify_spatial_feature_enhancement(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/spatial_feature_enhancement_result.json', result_path)
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

    # Criterion 2: Filtered band(s) exist beyond originals (25 pts)
    if result.get('has_filtered_band'):
        filtered_count = len(result.get('filtered_band_names', []))
        if filtered_count >= 2:
            score += 25
            feedback.append(f"Multiple filtered bands ({filtered_count}) (+25)")
        else:
            score += 20
            feedback.append("Filtered band found (+20)")
    elif result.get('total_band_count', 0) > result.get('original_band_count', 3):
        score += 15
        feedback.append("Extra bands found beyond originals (+15)")
    else:
        feedback.append("No filtered bands detected (0/25)")

    # Criterion 3: Filter type identifiable by band name (15 pts)
    filter_type = result.get('filter_type_detected', '')
    if filter_type:
        score += 15
        feedback.append(f"Filter type: {filter_type} (+15)")
    elif result.get('has_filtered_band'):
        score += 8
        feedback.append("Filtered band exists but type unclear (+8)")
    else:
        feedback.append("No filter type detected (0/15)")

    # Criterion 4: Original bands preserved (20 pts)
    if result.get('original_bands_preserved'):
        score += 20
        feedback.append("Original bands preserved (+20)")
    elif result.get('total_band_count', 0) > 0:
        score += 10
        feedback.append("Product has bands but originals not clearly preserved (+10)")
    else:
        feedback.append("Original bands not preserved (0/20)")

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
