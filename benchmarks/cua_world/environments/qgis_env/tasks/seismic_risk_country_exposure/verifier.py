#!/usr/bin/env python3
"""Verifier for seismic_risk_country_exposure task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_seismic_risk_country_exposure(traj, env_info, task_info):
    """
    Verify country-level seismic exposure analysis.

    Scoring (100 points):
    - Output file exists and is valid GeoJSON: 15 points (wrong-target gate)
    - All four required fields present (quake_count, mean_mag, max_mag, risk_tier): 15 points
    - Feature count within reasonable range of GT (±20%): 20 points
    - quake_count accuracy: >= 70% of GT countries within ±2: 25 points
    - risk_tier internal consistency and accuracy: 25 points

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/seismic_risk_result.json", temp_file.name)
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

    # ── GATE: file must exist and be new (created after task start) ────────────
    if not result.get('file_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file not found at /home/ga/GIS_Data/exports/country_seismic_exposure.geojson. No work completed.",
            "subscores": {"file_exists": False}
        }

    if not result.get('file_is_new', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file exists but was not created during this task session (pre-existing file). Wrong target.",
            "subscores": {"file_exists": True, "file_is_new": False}
        }

    # ── Independent re-validation: copy and re-parse the actual GeoJSON ────────
    independent_feature_count = 0
    independent_has_required = False
    geojson_temp = None
    try:
        geojson_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.geojson')
        geojson_temp.close()
        file_path = result.get('file_path', '/home/ga/GIS_Data/exports/country_seismic_exposure.geojson')
        copy_from_env(file_path, geojson_temp.name)
        with open(geojson_temp.name, 'r') as f:
            geojson_data = json.load(f)
        if geojson_data.get('type') == 'FeatureCollection':
            features = geojson_data.get('features', [])
            independent_feature_count = len(features)
            if features:
                req = {'quake_count', 'mean_mag', 'max_mag', 'risk_tier'}
                props = features[0].get('properties', {})
                independent_has_required = req.issubset(set(props.keys()))
    except Exception as e:
        logger.warning(f"Independent GeoJSON validation failed: {e}")
    finally:
        if geojson_temp and os.path.exists(geojson_temp.name):
            os.unlink(geojson_temp.name)

    # Use independent count to update result if better
    if independent_feature_count > 0:
        result['feature_count'] = independent_feature_count
    if independent_has_required:
        result['has_required_fields'] = True

    if not result.get('file_valid_geojson', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file exists but is not valid GeoJSON",
            "subscores": {"file_exists": True, "file_is_new": True, "valid_geojson": False}
        }

    score += 15
    subscores["file_valid"] = True
    feedback_parts.append("Valid new GeoJSON output found")

    # ── Criterion 2: Required fields (15 pts) ──────────────────────────────────
    if result.get('has_required_fields', False):
        score += 15
        subscores["required_fields"] = True
        feedback_parts.append("All required fields present (quake_count, mean_mag, max_mag, risk_tier)")
    else:
        fields_found = result.get('fields_found', '')
        subscores["required_fields"] = False
        feedback_parts.append(f"Missing required fields. Found: {fields_found or 'none'}")

    # ── Criterion 3: Feature count vs GT (20 pts) ──────────────────────────────
    feature_count = result.get('feature_count', 0)
    gt_feature_count = result.get('gt_feature_count', 0)

    if feature_count > 0 and gt_feature_count > 0:
        ratio = feature_count / gt_feature_count
        if 0.8 <= ratio <= 1.2:
            score += 20
            subscores["feature_count"] = True
            feedback_parts.append(f"Feature count {feature_count} within expected range (GT: {gt_feature_count})")
        elif 0.6 <= ratio <= 1.4:
            partial = 10
            score += partial
            subscores["feature_count"] = False
            feedback_parts.append(f"Feature count {feature_count} partially matches GT {gt_feature_count}")
        else:
            subscores["feature_count"] = False
            feedback_parts.append(f"Feature count {feature_count} far from GT {gt_feature_count}")
    elif feature_count > 0 and gt_feature_count == 0:
        # GT unavailable, give partial credit for any result
        score += 10
        subscores["feature_count"] = None
        feedback_parts.append(f"Feature count: {feature_count} (GT unavailable for comparison)")
    else:
        subscores["feature_count"] = False
        feedback_parts.append("No features in output")

    # ── Criterion 4: quake_count accuracy (25 pts) ─────────────────────────────
    qca = result.get('quake_count_accuracy', 0)
    if qca >= 70:
        score += 25
        subscores["quake_count_accuracy"] = True
        feedback_parts.append(f"quake_count accurate: {qca}% of countries within ±2 of GT")
    elif qca >= 50:
        partial = int(15 * (qca - 50) / 20)
        score += partial
        subscores["quake_count_accuracy"] = False
        feedback_parts.append(f"quake_count partially accurate: {qca}% of countries within ±2 of GT")
    else:
        subscores["quake_count_accuracy"] = False
        feedback_parts.append(f"quake_count inaccurate: only {qca}% within ±2 of GT")

    # ── Criterion 5: risk_tier consistency (25 pts) ────────────────────────────
    rta = result.get('risk_tier_accuracy', 0)
    if rta >= 75:
        score += 25
        subscores["risk_tier_accuracy"] = True
        feedback_parts.append(f"risk_tier classification correct: {rta}%")
    elif rta >= 50:
        partial = int(15 * (rta - 50) / 25)
        score += partial
        subscores["risk_tier_accuracy"] = False
        feedback_parts.append(f"risk_tier partially correct: {rta}%")
    else:
        subscores["risk_tier_accuracy"] = False
        feedback_parts.append(f"risk_tier classification incorrect: {rta}%")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
