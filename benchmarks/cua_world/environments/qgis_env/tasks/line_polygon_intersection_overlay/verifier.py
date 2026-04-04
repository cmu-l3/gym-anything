#!/usr/bin/env python3
"""Verifier for line_polygon_intersection_overlay task."""

import json
import tempfile
import os
import logging
import time

logger = logging.getLogger(__name__)


def verify_line_polygon_intersection_overlay(traj, env_info, task_info):
    """
    Verify that line-polygon intersection was performed correctly.

    Scoring (100 points):
    - File Exists (10pts)
    - Valid GeoJSON (10pts)
    - Has Line Features (15pts)
    - Feature Count >= 2 (15pts)
    - Feature Count == 3 (10pts) - Precision bonus
    - Combined Attributes (15pts) - Proves overlay, not just clip
    - Both Zones Represented (15pts) - Proves intersection handled both polygons
    - File Freshly Created (10pts) - Anti-gaming
    
    Pass threshold: 55 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
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
    
    analysis = result.get('analysis', {})
    
    # Criterion 1: File Exists (10 pts)
    if result.get('file_exists', False):
        score += 10
        subscores['file_exists'] = True
        feedback_parts.append("Output file found")
    else:
        subscores['file_exists'] = False
        feedback_parts.append("Output file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Valid GeoJSON (10 pts)
    if analysis.get('valid', False):
        score += 10
        subscores['valid_geojson'] = True
        feedback_parts.append("Valid GeoJSON")
    else:
        subscores['valid_geojson'] = False
        feedback_parts.append("Invalid or corrupted GeoJSON")
        # Can't proceed meaningfully if invalid
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: Has Line Features (15 pts)
    if analysis.get('all_lines', False):
        score += 15
        subscores['geometry_type'] = True
        feedback_parts.append("Geometry type correct (Lines)")
    else:
        # Partial credit if some lines exist but maybe mixed?
        # The script returns false if ANY non-line found.
        subscores['geometry_type'] = False
        feedback_parts.append("Incorrect geometry type (expected Lines)")

    # Criterion 4 & 5: Feature Count (15 + 10 pts)
    count = analysis.get('feature_count', 0)
    if count >= 2:
        score += 15
        subscores['min_count'] = True
        feedback_parts.append(f"Feature count sufficient ({count})")
        
        if count == 3:
            score += 10
            subscores['exact_count'] = True
            feedback_parts.append("Feature count exact (3)")
        else:
            subscores['exact_count'] = False
            feedback_parts.append(f"Feature count {count} (expected 3 for perfect split)")
    else:
        subscores['min_count'] = False
        feedback_parts.append(f"Feature count too low ({count})")

    # Criterion 6: Combined Attributes (15 pts)
    has_line = analysis.get('has_line_attr', False)
    has_poly = analysis.get('has_poly_attr', False)
    
    if has_line and has_poly:
        score += 15
        subscores['attributes'] = True
        feedback_parts.append("Attributes merged correctly (Lines + Polygons)")
    elif has_line:
        score += 5
        subscores['attributes'] = False
        feedback_parts.append("Only line attributes preserved (Clip used?)")
    elif has_poly:
        score += 5
        subscores['attributes'] = False
        feedback_parts.append("Only polygon attributes found")
    else:
        subscores['attributes'] = False
        feedback_parts.append("Attributes missing")

    # Criterion 7: Both Zones Represented (15 pts)
    zones = analysis.get('zones_found', [])
    if "Area A" in zones and "Area B" in zones:
        score += 15
        subscores['zones'] = True
        feedback_parts.append("Both zones (A & B) present in output")
    elif len(zones) > 0:
        score += 5
        subscores['zones'] = False
        feedback_parts.append(f"Only some zones found: {zones}")
    else:
        subscores['zones'] = False
        feedback_parts.append("No zone information found in output")

    # Criterion 8: Freshly Created (10 pts)
    task_start = result.get('task_start_time', 0)
    file_mtime = result.get('file_mtime', 0)
    # Allow 1 second clock skew/tolerance, though mtime usually distinct
    if file_mtime >= task_start:
        score += 10
        subscores['freshness'] = True
        feedback_parts.append("File created during task")
    else:
        subscores['freshness'] = False
        feedback_parts.append("File timestamp predates task start (Pre-existing?)")

    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }