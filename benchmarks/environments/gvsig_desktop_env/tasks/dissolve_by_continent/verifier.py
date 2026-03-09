#!/usr/bin/env python3
"""
Verifier for dissolve_by_continent task.

Task: Dissolve countries by CONTINENT field and export to
      /home/ga/gvsig_exports/continents_dissolved.shp

Scoring criteria (100 pts total):
  GATE: If feature count > 50 → score capped (not dissolved)
  1. Output file exists                            (20 pts)
  2. Feature count in range [5, 10]               (25 pts)
  3. CONTINENT field present in output             (25 pts)
  4. Africa, Asia, Europe all present as values    (30 pts, 10 each)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_dissolve_by_continent(traj, env_info, task_info):
    """
    Verify that countries were dissolved by continent and exported.

    Reads /tmp/dissolve_by_continent_result.json written by export_result.sh.

    Scoring (100 points total):
    - File exists: 20 pts
    - Feature count in [5, 10] (one per continent): 25 pts
    - CONTINENT field present: 25 pts
    - Africa present: 10 pts
    - Asia present: 10 pts
    - Europe present: 10 pts

    Gate: feature count > 50 means countries were not dissolved.
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
            copy_from_env('/tmp/dissolve_by_continent_result.json', temp_path)
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

    # Criterion 1: File exists (20 pts)
    if data.get('file_exists'):
        subscores['file_exists'] = 20
        score += 20
        feedback_parts.append("Output shapefile exists.")
    else:
        subscores['file_exists'] = 0
        feedback_parts.append("FAIL: /home/ga/gvsig_exports/continents_dissolved.shp not found.")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # GATE: If feature count > 50, the dissolve was not applied
    fc = data.get('feature_count')
    if fc is not None and fc > 50:
        return {
            "passed": False,
            "score": 15,
            "feedback": (
                f"GATE FAIL: Output has {fc} features, which indicates the country layer was exported "
                "WITHOUT dissolving. The dissolve-by-CONTINENT operation reduces ~177 countries to "
                "~7-8 continent features. Check that you used the Dissolve geoprocessing tool."
            ),
            "subscores": {'file_exists': 15, 'dissolve_gate': 0}
        }

    # Criterion 2: Feature count in [5, 10] (25 pts)
    src_cont_count = data.get('source_continent_count')
    if fc is not None:
        if 5 <= fc <= 10:
            subscores['feature_count'] = 25
            score += 25
            feedback_parts.append(
                f"Feature count: {fc} continent(s) — correct! "
                f"(Source has {src_cont_count or '~8'} distinct CONTINENT values.)"
            )
        elif fc == src_cont_count:
            subscores['feature_count'] = 25
            score += 25
            feedback_parts.append(
                f"Feature count: {fc} matches source continent count exactly."
            )
        elif 3 <= fc <= 15:
            subscores['feature_count'] = 15
            score += 15
            feedback_parts.append(
                f"WARN: Feature count {fc} is outside the tight expected range [5, 10]. "
                f"Source has {src_cont_count or '~8'} distinct CONTINENT values."
            )
        else:
            subscores['feature_count'] = 0
            feedback_parts.append(
                f"FAIL: Feature count {fc} is unexpected. "
                "Expected ~7-8 features after dissolving 177 countries by continent."
            )
    else:
        subscores['feature_count'] = 0
        feedback_parts.append("FAIL: Could not determine feature count.")

    # Criterion 3: CONTINENT field present (25 pts)
    if data.get('has_continent_field'):
        subscores['continent_field'] = 25
        score += 25
        cv = ', '.join(data.get('continent_values', []))
        feedback_parts.append(f"CONTINENT field present. Values: {cv}")
    else:
        subscores['continent_field'] = 0
        feedback_parts.append(
            "FAIL: CONTINENT field not found in output. "
            "Ensure the dissolve was performed on the CONTINENT field."
        )

    # Criterion 4: Africa, Asia, Europe present (30 pts, 10 each)
    continent_score = 0
    if data.get('africa_present'):
        continent_score += 10
        feedback_parts.append("Africa: present.")
    else:
        feedback_parts.append("FAIL: Africa not found in CONTINENT values.")

    if data.get('asia_present'):
        continent_score += 10
        feedback_parts.append("Asia: present.")
    else:
        feedback_parts.append("FAIL: Asia not found in CONTINENT values.")

    if data.get('europe_present'):
        continent_score += 10
        feedback_parts.append("Europe: present.")
    else:
        feedback_parts.append("FAIL: Europe not found in CONTINENT values.")

    subscores['continent_values'] = continent_score
    score += continent_score

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
