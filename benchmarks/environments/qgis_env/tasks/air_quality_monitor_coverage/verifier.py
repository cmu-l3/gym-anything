#!/usr/bin/env python3
"""Verifier for air_quality_monitor_coverage task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_air_quality_monitor_coverage(traj, env_info, task_info):
    """
    Verify EPA PM2.5 monitoring coverage gap analysis for California counties.

    Scoring (100 points):
    - Output GeoJSON exists and is valid: 15 points (wrong-target gate)
    - All four required fields present: 15 points
    - All 58 counties represented: 15 points
    - monitor_count accuracy (>= 65% within ±1 of GT): 25 points
    - coverage_status accuracy (>= 70%): 20 points
    - Monitoring coverage CSV exported: 10 points

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/aq_coverage_result.json", temp_file.name)
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
            "feedback": "Output GeoJSON not found at /home/ga/GIS_Data/exports/pm25_coverage_gaps.geojson",
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
    file_path = result.get('file_path', '/home/ga/GIS_Data/exports/pm25_coverage_gaps.geojson')
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
        feedback_parts.append("All required fields present (monitor_count, nearest_monitor_km, coverage_status, monitoring_density)")
    else:
        subscores["required_fields"] = False
        feedback_parts.append("Missing required fields (need: monitor_count, nearest_monitor_km, coverage_status, monitoring_density)")

    # ── Criterion 3: County coverage (15 pts) ──────────────────────────────────
    feature_count = result.get('feature_count', 0)
    gt_county_count = result.get('gt_county_count', 58)
    if gt_county_count == 0:
        gt_county_count = 58

    if feature_count >= 55:
        score += 15
        subscores["feature_count"] = True
        feedback_parts.append(f"All California counties represented: {feature_count}")
    elif feature_count >= 40:
        score += 8
        subscores["feature_count"] = False
        feedback_parts.append(f"Partial county coverage: {feature_count}/58")
    else:
        subscores["feature_count"] = False
        feedback_parts.append(f"Insufficient county coverage: {feature_count}/58")

    # ── Criterion 4: monitor_count accuracy (25 pts) ───────────────────────────
    mca = result.get('monitor_count_accuracy', 0)
    if mca >= 65:
        score += 25
        subscores["monitor_count_accuracy"] = True
        feedback_parts.append(f"monitor_count accurate: {mca}% of counties within ±1 of GT")
    elif mca >= 45:
        partial = int(12 * (mca - 45) / 20)
        score += partial
        subscores["monitor_count_accuracy"] = False
        feedback_parts.append(f"monitor_count partially accurate: {mca}%")
    else:
        subscores["monitor_count_accuracy"] = False
        feedback_parts.append(f"monitor_count inaccurate: {mca}% (check spatial join method)")

    # ── Criterion 5: coverage_status accuracy (20 pts) ─────────────────────────
    csa = result.get('coverage_status_accuracy', 0)
    if csa >= 70:
        score += 20
        subscores["coverage_status_accuracy"] = True
        feedback_parts.append(f"coverage_status classification correct: {csa}%")
    elif csa >= 50:
        partial = int(10 * (csa - 50) / 20)
        score += partial
        subscores["coverage_status_accuracy"] = False
        feedback_parts.append(f"coverage_status partially correct: {csa}%")
    else:
        subscores["coverage_status_accuracy"] = False
        feedback_parts.append(f"coverage_status incorrect: {csa}%")

    # ── Criterion 6: CSV report (10 pts) ───────────────────────────────────────
    if result.get('csv_valid', False):
        score += 10
        subscores["csv_output"] = True
        feedback_parts.append("monitoring_coverage_report.csv exported correctly")
    elif result.get('csv_exists', False):
        score += 3
        subscores["csv_output"] = False
        feedback_parts.append("CSV exists but missing required columns (need: county_name, fips, monitor_count, coverage_status, ...)")
    else:
        subscores["csv_output"] = False
        feedback_parts.append("monitoring_coverage_report.csv not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
