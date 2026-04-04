#!/usr/bin/env python3
"""Verifier for invasive_species_state_expansion task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_invasive_species_state_expansion(traj, env_info, task_info):
    """
    Verify invasive species range shift analysis by state.

    Scoring (100 points):
    - Output GeoJSON exists and is valid: 15 points (wrong-target gate)
    - All four required fields present: 15 points
    - Feature count covers expected states with occurrences: 15 points
    - Period count accuracy (>= 60% of states within ±1 for both periods): 25 points
    - invasion_status classification accuracy (>= 60%): 20 points
    - Summary CSV exported correctly: 10 points

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/invasion_result.json", temp_file.name)
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
            "feedback": "Output GeoJSON not found at /home/ga/GIS_Data/exports/invasion_status_by_state.geojson",
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
    file_path = result.get('file_path', '/home/ga/GIS_Data/exports/invasion_status_by_state.geojson')
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
        feedback_parts.append("All required fields present (count_2005_2012, count_2016_2023, pct_change, invasion_status)")
    else:
        subscores["required_fields"] = False
        feedback_parts.append("Missing required fields (need: count_2005_2012, count_2016_2023, pct_change, invasion_status)")

    # ── Criterion 3: Feature count (15 pts) ────────────────────────────────────
    feature_count = result.get('feature_count', 0)
    gt_state_count = result.get('gt_state_count', 0)

    if gt_state_count > 0:
        ratio = feature_count / gt_state_count if gt_state_count > 0 else 0
        if ratio >= 0.8:
            score += 15
            subscores["feature_count"] = True
            feedback_parts.append(f"State count {feature_count} matches expected ~{gt_state_count} states with occurrences")
        elif ratio >= 0.5:
            score += 7
            subscores["feature_count"] = False
            feedback_parts.append(f"State count {feature_count} partially covers expected {gt_state_count}")
        else:
            subscores["feature_count"] = False
            feedback_parts.append(f"Too few states: {feature_count} vs expected {gt_state_count}")
    elif feature_count >= 10:
        score += 7
        subscores["feature_count"] = None
        feedback_parts.append(f"State count: {feature_count} (GT unavailable)")
    else:
        subscores["feature_count"] = False
        feedback_parts.append(f"Too few states in output: {feature_count}")

    # ── Criterion 4: Period count accuracy (25 pts) ─────────────────────────────
    count_acc = result.get('count_accuracy', 0)
    if count_acc >= 60:
        score += 25
        subscores["count_accuracy"] = True
        feedback_parts.append(f"Period occurrence counts accurate: {count_acc}% within ±1 of GT")
    elif count_acc >= 40:
        partial = int(12 * (count_acc - 40) / 20)
        score += partial
        subscores["count_accuracy"] = False
        feedback_parts.append(f"Period counts partially accurate: {count_acc}%")
    else:
        subscores["count_accuracy"] = False
        feedback_parts.append(f"Period counts inaccurate: {count_acc}% (check year-based filtering)")

    # ── Criterion 5: invasion_status accuracy (20 pts) ─────────────────────────
    status_acc = result.get('status_accuracy', 0)
    if status_acc >= 60:
        score += 20
        subscores["status_accuracy"] = True
        feedback_parts.append(f"invasion_status classification correct: {status_acc}%")
    elif status_acc >= 40:
        partial = int(10 * (status_acc - 40) / 20)
        score += partial
        subscores["status_accuracy"] = False
        feedback_parts.append(f"invasion_status partially correct: {status_acc}%")
    else:
        subscores["status_accuracy"] = False
        feedback_parts.append(f"invasion_status classification incorrect: {status_acc}%")

    # ── Criterion 6: Summary CSV (10 pts) ──────────────────────────────────────
    if result.get('csv_valid', False):
        score += 10
        subscores["csv_output"] = True
        feedback_parts.append("invasion_summary.csv exported correctly")
    elif result.get('csv_exists', False):
        score += 3
        subscores["csv_output"] = False
        feedback_parts.append("CSV exists but missing required columns (invasion_status, state_count, total_occurrences_recent)")
    else:
        subscores["csv_output"] = False
        feedback_parts.append("invasion_summary.csv not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
