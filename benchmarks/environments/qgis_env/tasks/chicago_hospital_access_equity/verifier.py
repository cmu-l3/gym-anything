#!/usr/bin/env python3
"""Verifier for chicago_hospital_access_equity task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_chicago_hospital_access_equity(traj, env_info, task_info):
    """
    Verify hospital access equity analysis for Chicago community areas.

    Scoring (100 points):
    - Output GeoJSON exists and is valid: 15 points (wrong-target gate)
    - All three required fields present: 15 points
    - All 77 community areas represented: 15 points
    - nearest_hosp_km accuracy (>= 60% within ±1 km of GT): 20 points
    - access_tier classification accuracy (>= 65%): 20 points
    - Summary CSV exported with correct structure: 15 points

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/hospital_access_result.json", temp_file.name)
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
            "feedback": "Output GeoJSON not found at /home/ga/GIS_Data/exports/hospital_access_equity.geojson",
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
    file_path = result.get('file_path', '/home/ga/GIS_Data/exports/hospital_access_equity.geojson')
    try:
        geojson_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.geojson')
        geojson_temp.close()
        copy_from_env(file_path, geojson_temp.name)
        with open(geojson_temp.name, 'r') as f:
            geojson_data = json.load(f)
        os.unlink(geojson_temp.name)
        if geojson_data.get('type') == 'FeatureCollection':
            independent_count = len(geojson_data.get('features', []))
            # Override with independent count for reliability
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
        feedback_parts.append("All required fields present (nearest_hosp_km, hosp_count_5km, access_tier)")
    else:
        subscores["required_fields"] = False
        feedback_parts.append("Missing required fields (need: nearest_hosp_km, hosp_count_5km, access_tier)")

    # ── Criterion 3: Feature count (15 pts) ────────────────────────────────────
    feature_count = result.get('feature_count', 0)
    gt_ca_count = result.get('gt_ca_count', 77)
    if gt_ca_count == 0:
        gt_ca_count = 77

    if feature_count >= 70:
        score += 15
        subscores["feature_count"] = True
        feedback_parts.append(f"All community areas represented: {feature_count}")
    elif feature_count >= 50:
        score += 8
        subscores["feature_count"] = False
        feedback_parts.append(f"Partial community area coverage: {feature_count}/77")
    else:
        subscores["feature_count"] = False
        feedback_parts.append(f"Insufficient community areas: {feature_count}/77")

    # ── Criterion 4: nearest_hosp_km accuracy (20 pts) ─────────────────────────
    dist_acc = result.get('nearest_dist_accuracy', 0)
    if dist_acc >= 60:
        score += 20
        subscores["distance_accuracy"] = True
        feedback_parts.append(f"Hospital distance values accurate: {dist_acc}% within ±1 km of GT")
    elif dist_acc >= 40:
        partial = int(10 * (dist_acc - 40) / 20)
        score += partial
        subscores["distance_accuracy"] = False
        feedback_parts.append(f"Hospital distances partially accurate: {dist_acc}% within ±1 km")
    else:
        subscores["distance_accuracy"] = False
        feedback_parts.append(f"Hospital distances inaccurate: {dist_acc}% within ±1 km (check projected CRS)")

    # ── Criterion 5: access_tier accuracy (20 pts) ─────────────────────────────
    tier_acc = result.get('tier_accuracy', 0)
    if tier_acc >= 65:
        score += 20
        subscores["tier_accuracy"] = True
        feedback_parts.append(f"access_tier classification correct: {tier_acc}%")
    elif tier_acc >= 45:
        partial = int(10 * (tier_acc - 45) / 20)
        score += partial
        subscores["tier_accuracy"] = False
        feedback_parts.append(f"access_tier classification partially correct: {tier_acc}%")
    else:
        subscores["tier_accuracy"] = False
        feedback_parts.append(f"access_tier classification incorrect: {tier_acc}%")

    # ── Criterion 6: Summary CSV (15 pts) ──────────────────────────────────────
    if result.get('csv_valid', False):
        score += 15
        subscores["csv_output"] = True
        feedback_parts.append("access_tier_summary.csv exported with correct columns")
    elif result.get('csv_exists', False):
        score += 5
        subscores["csv_output"] = False
        feedback_parts.append("CSV exists but missing required columns (need: access_tier, community_count, total_population)")
    else:
        subscores["csv_output"] = False
        feedback_parts.append("Summary CSV not found at /home/ga/GIS_Data/exports/access_tier_summary.csv")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
