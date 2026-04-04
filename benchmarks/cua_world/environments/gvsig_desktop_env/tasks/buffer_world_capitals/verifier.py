#!/usr/bin/env python3
"""
Verifier for buffer_world_capitals task.

Task: Buffer Admin-0 capital cities by 2 geographic degrees,
      export to /home/ga/gvsig_exports/capital_buffers.shp

Scoring criteria (100 pts total):
  1. Output file exists                            (15 pts)
  2. Geometry type is polygon/multipolygon         (20 pts)  [GATE: non-polygon exits early]
  3. Feature count in expected range               (40 pts)  [primary criterion]
  4. Output has NAME attribute from source         (25 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_buffer_world_capitals(traj, env_info, task_info):
    """
    Verify that capital cities were buffered and exported correctly.

    Reads /tmp/buffer_world_capitals_result.json written by export_result.sh.

    Scoring (100 points total):
    - File exists: 15 pts
    - Geometry is polygon (buffer applied): 20 pts [GATE: non-polygon returns immediately]
    - Feature count matches expected capital count: 40 pts
    - NAME field present (original attributes preserved): 25 pts

    Pass threshold: 65 points
    (Requires correct geometry + correct count + partial attributes, or all 4 criteria)
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
            copy_from_env('/tmp/buffer_world_capitals_result.json', temp_path)
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

    # Criterion 1: File exists (15 pts)
    if data.get('file_exists'):
        subscores['file_exists'] = 15
        score += 15
        feedback_parts.append("Output shapefile exists.")
    else:
        subscores['file_exists'] = 0
        feedback_parts.append("FAIL: /home/ga/gvsig_exports/capital_buffers.shp not found.")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # Criterion 2: Geometry type is polygon (20 pts)
    # GATE: If geometry is not polygon, the buffer was not applied — return immediately
    is_poly = data.get('is_polygon', False)
    geom_type = data.get('geom_type', 'unknown')
    if is_poly:
        subscores['geometry_polygon'] = 20
        score += 20
        feedback_parts.append(f"Geometry type is polygon ({geom_type}). Buffer was applied!")
    else:
        subscores['geometry_polygon'] = 0
        if geom_type and 'POINT' in geom_type.upper():
            feedback_parts.append(
                "FAIL: Output contains POINT geometry, not POLYGON. "
                "The buffer operation was not applied — the original point layer was exported instead."
            )
        else:
            feedback_parts.append(
                f"FAIL: Expected polygon geometry but got '{geom_type}'. "
                "The buffer operation may not have been completed correctly."
            )
        # Gate: non-polygon means buffer was never applied
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # Criterion 3: Feature count in expected range (40 pts — primary criterion)
    fc = data.get('feature_count')
    src_count = data.get('source_capital_count')

    if fc is not None:
        if src_count and abs(fc - src_count) <= 5:
            subscores['feature_count'] = 40
            score += 40
            feedback_parts.append(
                f"Feature count {fc} matches expected Admin-0 capital count {src_count}."
            )
        elif 130 <= fc <= 280:
            subscores['feature_count'] = 28
            score += 28
            expected = src_count or '~200'
            feedback_parts.append(
                f"Feature count {fc} is in plausible capital range (expected ~{expected})."
            )
        elif fc < 130:
            subscores['feature_count'] = 0
            feedback_parts.append(
                f"FAIL: Feature count {fc} is too low. "
                "Ensure you filtered to 'Admin-0 capital' features and that all capitals were buffered."
            )
        else:
            subscores['feature_count'] = 15
            score += 15
            feedback_parts.append(
                f"WARN: Feature count {fc} is high (expected ~{src_count or 200}). "
                "Check whether all populated place types were buffered instead of only Admin-0 capitals."
            )
    else:
        subscores['feature_count'] = 0
        feedback_parts.append("FAIL: Could not determine feature count.")

    # Criterion 4: NAME field present (25 pts)
    if data.get('has_name_field'):
        subscores['name_field'] = 25
        score += 25
        feedback_parts.append("NAME attribute field present — original attributes preserved.")
    else:
        subscores['name_field'] = 0
        fields_str = ', '.join(data.get('fields', [])[:10])
        feedback_parts.append(
            f"FAIL: NAME field not found in output. "
            f"Available fields: {fields_str}. "
            "Ensure original attributes from the point layer were carried into the buffer output."
        )

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
