#!/usr/bin/env python3
"""Verifier for urban_park_coverage_equity task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_urban_park_coverage_equity(traj, env_info, task_info):
    """
    Verify park coverage equity analysis for Portland census tracts.

    Scoring (100 points):
    - Output GeoJSON exists and is valid: 15 points (wrong-target gate)
    - All four required fields present: 15 points
    - Feature count covers expected tracts: 10 points
    - Area values indicate projected CRS was used (not geographic degrees): 15 points
    - park_pct values accurate to within ±3pp of GT (>= 55%): 20 points
    - greenspace_tier classification accurate (>= 60%): 15 points
    - Equity summary CSV exported: 10 points

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/park_coverage_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    logger.info(f"Task result: {result}")

    score = 0
    feedback_parts = []
    subscores = {}

    # ── GATE: GeoJSON exists and valid (15 pts) ────────────────────────────────
    if not result.get('file_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output GeoJSON not found at /home/ga/GIS_Data/exports/park_coverage_by_tract.geojson",
            "subscores": {"file_exists": False}
        }

    if not result.get('file_is_new', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file was not created during this task session (pre-existing file detected)",
            "subscores": {"file_exists": True, "file_is_new": False}
        }

    # Pattern 8: independently re-validate GeoJSON from env
    file_path = result.get('file_path', '/home/ga/GIS_Data/exports/park_coverage_by_tract.geojson')
    try:
        geojson_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.geojson')
        geojson_temp.close()
        copy_from_env(file_path, geojson_temp.name)
        with open(geojson_temp.name, 'r') as f:
            geojson_data = json.load(f)
        os.unlink(geojson_temp.name)
        if geojson_data.get('type') == 'FeatureCollection':
            independent_count = len(geojson_data.get('features', []))
            if independent_count > 0:
                result['feature_count'] = independent_count
    except Exception:
        pass  # Fall back to export-script values

    if not result.get('file_valid_geojson', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file is not valid GeoJSON",
            "subscores": {"file_exists": True, "valid_geojson": False}
        }

    score += 15
    subscores["file_valid"] = True
    feedback_parts.append("Valid GeoJSON output found")

    # ── Criterion 2: Required fields (15 pts) ──────────────────────────────────
    if result.get('has_required_fields', False):
        score += 15
        subscores["required_fields"] = True
        feedback_parts.append("All required fields present (park_area_sqm, tract_area_sqm, park_pct, greenspace_tier)")
    else:
        subscores["required_fields"] = False
        feedback_parts.append("Missing required fields (need: park_area_sqm, tract_area_sqm, park_pct, greenspace_tier)")

    # ── Criterion 3: Feature count (10 pts) ────────────────────────────────────
    feature_count = result.get('feature_count', 0)
    gt_tract_count = result.get('gt_tract_count', 0)

    if gt_tract_count > 0:
        ratio = feature_count / gt_tract_count
        if ratio >= 0.85:
            score += 10
            subscores["feature_count"] = True
            feedback_parts.append(f"Tract coverage complete: {feature_count}/{gt_tract_count}")
        elif ratio >= 0.5:
            score += 5
            subscores["feature_count"] = False
            feedback_parts.append(f"Partial tract coverage: {feature_count}/{gt_tract_count}")
        else:
            subscores["feature_count"] = False
            feedback_parts.append(f"Insufficient tracts: {feature_count} vs expected {gt_tract_count}")
    elif feature_count >= 50:
        score += 7
        subscores["feature_count"] = None
        feedback_parts.append(f"Tract count: {feature_count}")
    else:
        subscores["feature_count"] = False
        feedback_parts.append(f"Too few tracts: {feature_count}")

    # ── Criterion 4: Projected CRS used (15 pts) ───────────────────────────────
    uses_proj = result.get('uses_projected_crs', 0)
    if uses_proj:
        score += 15
        subscores["projected_crs"] = True
        feedback_parts.append("Area values indicate projected CRS used (areas in square meters)")
    else:
        subscores["projected_crs"] = False
        feedback_parts.append("Area values suggest geographic CRS used (areas in sq degrees) — reproject data first")

    # ── Criterion 5: park_pct accuracy (20 pts) ────────────────────────────────
    ppa = result.get('park_pct_accuracy', 0)
    if ppa >= 55:
        score += 20
        subscores["park_pct_accuracy"] = True
        feedback_parts.append(f"park_pct accurate: {ppa}% of tracts within ±3pp of GT")
    elif ppa >= 35:
        partial = int(10 * (ppa - 35) / 20)
        score += partial
        subscores["park_pct_accuracy"] = False
        feedback_parts.append(f"park_pct partially accurate: {ppa}%")
    else:
        subscores["park_pct_accuracy"] = False
        feedback_parts.append(f"park_pct inaccurate: {ppa}% (check intersection with projected layers)")

    # ── Criterion 6: tier accuracy (15 pts) ────────────────────────────────────
    tier_acc = result.get('tier_accuracy', 0)
    if tier_acc >= 60:
        score += 15
        subscores["tier_accuracy"] = True
        feedback_parts.append(f"greenspace_tier classification correct: {tier_acc}%")
    elif tier_acc >= 40:
        partial = int(8 * (tier_acc - 40) / 20)
        score += partial
        subscores["tier_accuracy"] = False
        feedback_parts.append(f"greenspace_tier partially correct: {tier_acc}%")
    else:
        subscores["tier_accuracy"] = False
        feedback_parts.append(f"greenspace_tier classification incorrect: {tier_acc}%")

    # ── Criterion 7: Equity summary CSV (10 pts) ───────────────────────────────
    if result.get('csv_valid', False):
        score += 10
        subscores["csv_output"] = True
        feedback_parts.append("greenspace_equity_summary.csv exported correctly")
    elif result.get('csv_exists', False):
        score += 3
        subscores["csv_output"] = False
        feedback_parts.append("CSV exists but missing required columns")
    else:
        subscores["csv_output"] = False
        feedback_parts.append("greenspace_equity_summary.csv not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
