#!/usr/bin/env python3
"""
Verifier for emergency_medical_accessibility task.

Scoring (100 points, pass >= 60):
- GeoJSON exists and created during task:    10 pts
- Valid GeoJSON FeatureCollection:            10 pts
- All 7 required fields present:             10 pts
- Feature count >= 80% of GT:                10 pts
- nearest_facility_km accuracy >= 65%:       20 pts
- nearest_road_km accuracy >= 65%:           15 pts
- isolation_score accuracy >= 55%:           10 pts
- priority_class accuracy >= 60%:            10 pts
- CSV summary exists with correct columns:    5 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_emergency_medical_accessibility(traj, env_info, task_info):
    """Verify emergency medical accessibility analysis results."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Read the result JSON produced by export_result.sh
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/accessibility_result.json", temp_file.name)
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

    # GATE: file must exist
    if not result.get('file_exists', False):
        return {
            "passed": False, "score": 0,
            "feedback": "Output GeoJSON not found.",
            "subscores": {"file_exists": False}
        }

    # GATE: file must be new
    if not result.get('file_is_new', False):
        return {
            "passed": False, "score": 0,
            "feedback": "Output file exists but was not created during this task session.",
            "subscores": {"file_exists": True, "file_is_new": False}
        }

    # Independent re-validation: copy and re-parse the actual GeoJSON
    independent_count = 0
    independent_has_fields = False
    geojson_temp = None
    try:
        geojson_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.geojson')
        geojson_temp.close()
        file_path = result.get('file_path',
                               '/home/ga/GIS_Data/exports/community_accessibility.geojson')
        copy_from_env(file_path, geojson_temp.name)
        with open(geojson_temp.name, 'r') as f:
            geojson_data = json.load(f)
        if geojson_data.get('type') == 'FeatureCollection':
            features = geojson_data.get('features', [])
            independent_count = len(features)
            if features:
                req = {'name', 'country', 'population', 'nearest_facility_km',
                       'nearest_road_km', 'isolation_score', 'priority_class'}
                props = features[0].get('properties', {})
                independent_has_fields = req.issubset(set(props.keys()))
    except Exception as e:
        logger.warning(f"Independent GeoJSON validation failed: {e}")
    finally:
        if geojson_temp and os.path.exists(geojson_temp.name):
            os.unlink(geojson_temp.name)

    if independent_count > 0:
        result['feature_count'] = independent_count
    if independent_has_fields:
        result['has_required_fields'] = True

    # Criterion 1: Valid GeoJSON (10 pts)
    if not result.get('file_valid_geojson', False):
        return {
            "passed": False, "score": 0,
            "feedback": "Output is not valid GeoJSON.",
            "subscores": {"file_exists": True, "file_is_new": True, "valid": False}
        }
    score += 10
    subscores["file_valid_new"] = True
    feedback_parts.append("Valid new GeoJSON output")

    # Criterion 2: Required fields (10 pts)
    if result.get('has_required_fields', False):
        score += 10
        subscores["required_fields"] = True
        feedback_parts.append("All 7 required fields present")
    else:
        found = result.get('fields_found', '')
        subscores["required_fields"] = False
        feedback_parts.append(f"Missing fields. Found: {found or 'none'}")

    # Criterion 3: Feature count (10 pts)
    feat_count = result.get('feature_count', 0)
    gt_count = result.get('gt_community_count', 0)
    if feat_count > 0 and gt_count > 0:
        ratio = feat_count / gt_count
        if ratio >= 0.8:
            score += 10
            feedback_parts.append(f"Feature count {feat_count} (GT: {gt_count})")
        elif ratio >= 0.6:
            score += 5
            feedback_parts.append(f"Partial count: {feat_count}/{gt_count}")
        else:
            feedback_parts.append(f"Low count: {feat_count}/{gt_count}")
    elif feat_count > 0:
        score += 5
        feedback_parts.append(f"Features: {feat_count} (GT unavailable)")

    # Criterion 4: nearest_facility_km accuracy (20 pts)
    fda = result.get('facility_dist_accuracy', 0)
    if fda >= 65:
        score += 20
        feedback_parts.append(f"Facility dist accuracy: {fda}%")
    elif fda >= 45:
        partial = int(10 * (fda - 45) / 20)
        score += partial
        feedback_parts.append(f"Partial facility accuracy: {fda}%")
    else:
        feedback_parts.append(f"Low facility accuracy: {fda}%")

    # Criterion 5: nearest_road_km accuracy (15 pts)
    rda = result.get('road_dist_accuracy', 0)
    if rda >= 65:
        score += 15
        feedback_parts.append(f"Road dist accuracy: {rda}%")
    elif rda >= 45:
        partial = int(8 * (rda - 45) / 20)
        score += partial
        feedback_parts.append(f"Partial road accuracy: {rda}%")
    else:
        feedback_parts.append(f"Low road accuracy: {rda}%")

    # Criterion 6: isolation_score accuracy (10 pts)
    isa = result.get('isolation_accuracy', 0)
    if isa >= 55:
        score += 10
        feedback_parts.append(f"Isolation score accuracy: {isa}%")
    elif isa >= 35:
        score += 5
        feedback_parts.append(f"Partial isolation accuracy: {isa}%")
    else:
        feedback_parts.append(f"Low isolation accuracy: {isa}%")

    # Criterion 7: priority_class accuracy (10 pts)
    pa = result.get('priority_accuracy', 0)
    if pa >= 60:
        score += 10
        feedback_parts.append(f"Priority accuracy: {pa}%")
    elif pa >= 40:
        score += 5
        feedback_parts.append(f"Partial priority accuracy: {pa}%")
    else:
        feedback_parts.append(f"Low priority accuracy: {pa}%")

    # Criterion 8: CSV summary (5 pts)
    if result.get('csv_valid', False):
        score += 5
        feedback_parts.append("CSV summary valid")
    elif result.get('csv_exists', False):
        score += 2
        feedback_parts.append("CSV exists but invalid columns")
    else:
        feedback_parts.append("CSV not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
