#!/usr/bin/env python3
"""Verifier for cartographic_reprojection task.

Scoring breakdown (must sum to exactly 100):
  Product saved in DIMAP format:                  15 pts
  CRS changed to projected coordinate system:     25 pts
  Spatial subset applied (dimensions changed):    20 pts
  Bands preserved in output:                      15 pts
  GeoTIFF exported:                               15 pts
  GeoTIFF has non-trivial size:                   10 pts
                                           TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import tempfile


def verify_cartographic_reprojection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/cartographic_reprojection_result.json', result_path)
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

    # Criterion 2: CRS changed to projected coordinate system (25 pts)
    if result.get('crs_changed'):
        crs_wkt = result.get('crs_wkt', '').lower()
        # Check if it's specifically a projected CRS (UTM, etc.)
        is_projected = any(kw in crs_wkt for kw in [
            'utm', 'mercator', 'transverse', 'lambert', 'albers',
            'projcs', 'projected'
        ])
        if is_projected:
            score += 25
            feedback.append("CRS changed to projected system (+25)")
        else:
            score += 20
            feedback.append("CRS changed but projection type unclear (+20)")
    elif result.get('crs_wkt'):
        score += 5
        feedback.append("CRS present but may not have changed (+5)")
    else:
        feedback.append("No CRS information detected (0/25)")

    # Criterion 3: Spatial subset applied (20 pts)
    if result.get('dimensions_changed'):
        w = result.get('raster_width', 0)
        h = result.get('raster_height', 0)
        ow = result.get('original_width', 0)
        oh = result.get('original_height', 0)
        if ow > 0 and oh > 0:
            # Subset should be smaller, but reprojection may change dims too
            area_ratio = (w * h) / max(ow * oh, 1)
            if area_ratio < 0.8:
                score += 20
                feedback.append(f"Subset applied ({w}x{h} from {ow}x{oh}) (+20)")
            else:
                score += 15
                feedback.append(f"Dimensions changed ({w}x{h} from {ow}x{oh}) (+15)")
        else:
            score += 15
            feedback.append("Dimensions changed (original unknown) (+15)")
    elif result.get('raster_width', 0) > 0:
        score += 5
        feedback.append("Product has dimensions but no change detected (+5)")
    else:
        feedback.append("No dimension change detected (0/20)")

    # Criterion 4: Bands preserved in output (15 pts)
    band_count = result.get('band_count', 0)
    if band_count >= 3:
        score += 15
        feedback.append(f"Bands preserved ({band_count} bands) (+15)")
    elif band_count >= 1:
        score += 10
        feedback.append(f"Some bands present ({band_count}) (+10)")
    else:
        feedback.append("No bands in output (0/15)")

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
