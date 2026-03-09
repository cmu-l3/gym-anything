#!/usr/bin/env python3
"""
Verifier for reproject_rivers_utm33n task.

Task: Reproject Natural Earth rivers from WGS84 to EPSG:32633 (UTM Zone 33N)
      and export to /home/ga/gvsig_exports/rivers_utm33n.shp

Scoring criteria (100 pts total):
  1. Output file exists                          (20 pts)
  2. CRS is EPSG:32633 (UTM 33N)                (40 pts)
  3. Feature count matches source                (25 pts)
  4. Coordinates appear metric (not degrees)     (15 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_reproject_rivers_utm33n(traj, env_info, task_info):
    """
    Verify that rivers shapefile was reprojected to UTM Zone 33N (EPSG:32633).

    Reads /tmp/reproject_rivers_utm33n_result.json written by export_result.sh.

    Scoring (100 points total):
    - File exists at expected path: 20 pts
    - CRS is EPSG:32633: 40 pts (main criterion)
    - Feature count matches source: 25 pts
    - Coordinates appear metric (UTM meters, not degrees): 15 pts

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "ERROR: copy_from_env not available in env_info.",
            "subscores": {}
        }

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        try:
            copy_from_env('/tmp/reproject_rivers_utm33n_result.json', temp_path)
            with open(temp_path, 'r') as f:
                data = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except OSError:
                pass
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result JSON: {e}",
            "subscores": {}
        }

    logger.info(f"Task result: {data}")

    score = 0
    subscores = {}
    feedback_parts = []

    # Criterion 1: Output file exists (20 pts)
    if data.get('file_exists'):
        subscores['file_exists'] = 20
        score += 20
        feedback_parts.append("Output shapefile exists.")
    else:
        subscores['file_exists'] = 0
        feedback_parts.append("FAIL: Output file /home/ga/gvsig_exports/rivers_utm33n.shp not found.")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # Criterion 2: CRS is EPSG:32633 (40 pts)
    epsg_code = data.get('epsg_code')
    crs_wkt = data.get('crs_wkt', '') or ''
    utm33_confirmed = (
        epsg_code == 32633 or
        ('utm' in crs_wkt.lower() and ('zone 33' in crs_wkt.lower() or 'zone33' in crs_wkt.lower()))
    )
    if utm33_confirmed:
        subscores['crs_correct'] = 40
        score += 40
        feedback_parts.append(f"CRS is UTM Zone 33N (EPSG:{epsg_code}). Correct!")
    elif epsg_code == 4326 or ('geographiccs' in crs_wkt.lower() and 'utm' not in crs_wkt.lower()):
        subscores['crs_correct'] = 0
        feedback_parts.append(
            f"FAIL: CRS is WGS84 geographic (EPSG:{epsg_code}). "
            "The layer was NOT reprojected — it is still in its original coordinate system."
        )
    else:
        subscores['crs_correct'] = 0
        feedback_parts.append(
            f"FAIL: CRS is not EPSG:32633. Found EPSG={epsg_code}."
        )

    # Criterion 3: Feature count matches source (25 pts)
    out_count = data.get('feature_count')
    src_count = data.get('source_feature_count')
    if out_count is not None and src_count is not None:
        if out_count == src_count:
            subscores['feature_count'] = 25
            score += 25
            feedback_parts.append(f"Feature count correct: {out_count} features (matches source).")
        elif abs(out_count - src_count) <= 2:
            subscores['feature_count'] = 15
            score += 15
            feedback_parts.append(
                f"Feature count close: {out_count} vs source {src_count} (minor discrepancy tolerated)."
            )
        else:
            subscores['feature_count'] = 0
            feedback_parts.append(
                f"FAIL: Feature count mismatch. Output has {out_count}, source has {src_count}."
            )
    elif out_count is not None and out_count > 5:
        subscores['feature_count'] = 10
        score += 10
        feedback_parts.append(f"Feature count: {out_count} (source count unavailable for comparison).")
    else:
        subscores['feature_count'] = 0
        feedback_parts.append(f"FAIL: Feature count is {out_count} or unavailable.")

    # Criterion 4: Coordinate range indicates metric (15 pts)
    # UTM meters: values are in hundreds of thousands to millions
    # Geographic degrees: values in [-180, 180]
    # We check the CRS WKT for unit hint, or rely on EPSG code already confirmed
    if utm33_confirmed:
        # Already confirmed UTM, coordinates are metric by definition
        subscores['coord_range'] = 15
        score += 15
        feedback_parts.append("Coordinate system confirmed metric (UTM meters).")
    else:
        # Try to assess from CRS WKT
        if crs_wkt and 'metre' in crs_wkt.lower():
            subscores['coord_range'] = 15
            score += 15
            feedback_parts.append("Coordinate units confirmed: metre.")
        elif crs_wkt and 'degree' in crs_wkt.lower():
            subscores['coord_range'] = 0
            feedback_parts.append("FAIL: Coordinate units are degrees — layer not in a projected CRS.")
        else:
            subscores['coord_range'] = 0
            feedback_parts.append("WARN: Could not confirm coordinate units from CRS.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
