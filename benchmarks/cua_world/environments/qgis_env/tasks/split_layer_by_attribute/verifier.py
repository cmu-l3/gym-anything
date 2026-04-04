#!/usr/bin/env python3
"""Verifier for split_layer_by_attribute task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_split_layer_by_attribute(traj, env_info, task_info):
    """
    Verify that the vector layer was correctly split by continent.

    Scoring (100 points):
    - Output files exist: 15 pts
    - Files created during task (anti-gaming): 10 pts
    - Correct number of files (6-9): 15 pts
    - All files valid GeoJSON: 15 pts
    - Split consistency (each file contains only 1 continent): 20 pts
    - Expected continents present (Africa, Asia, Europe, etc.): 15 pts
    - Total feature count plausible (150-200): 10 pts

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_continents = set(metadata.get('expected_continents', []))

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

    analysis = result.get('analysis', {})
    score = 0
    feedback_parts = []
    subscores = {}

    # 1. Output files exist (15 pts)
    files_found = analysis.get('files_found', 0)
    if files_found > 0:
        score += 15
        subscores['files_exist'] = True
        feedback_parts.append(f"Found {files_found} output files")
    else:
        feedback_parts.append("No output files found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Files created during task (10 pts)
    new_files = analysis.get('files_created_during_task', 0)
    if new_files >= files_found and files_found > 0:
        score += 10
        subscores['new_files'] = True
        feedback_parts.append("All files newly created")
    elif new_files > 0:
        score += 5
        subscores['new_files'] = False
        feedback_parts.append("Some files pre-existed")
    else:
        subscores['new_files'] = False
        feedback_parts.append("Files not created during task execution")

    # 3. Correct number of files (15 pts)
    # Natural Earth split usually yields 7 continents + "Seven seas" = 8 files
    min_files = metadata.get('min_files', 6)
    max_files = metadata.get('max_files', 9)
    if min_files <= files_found <= max_files:
        score += 15
        subscores['count_correct'] = True
        feedback_parts.append("File count correct")
    else:
        subscores['count_correct'] = False
        feedback_parts.append(f"File count {files_found} outside range [{min_files}, {max_files}]")

    # 4. Valid GeoJSON (15 pts)
    valid_count = analysis.get('valid_geojson_count', 0)
    if valid_count == files_found and files_found > 0:
        score += 15
        subscores['valid_geojson'] = True
    else:
        partial = int(15 * (valid_count / files_found)) if files_found else 0
        score += partial
        subscores['valid_geojson'] = False
        feedback_parts.append(f"{files_found - valid_count} invalid files")

    # 5. Split Consistency (20 pts)
    # Does each file contain features for only ONE continent?
    split_correct = analysis.get('split_correct', False)
    if split_correct and files_found > 0:
        score += 20
        subscores['split_consistent'] = True
        feedback_parts.append("Split by attribute correct (homogeneous files)")
    else:
        subscores['split_consistent'] = False
        feedback_parts.append("Split inconsistent (files contain mixed attributes)")

    # 6. Expected Continents (15 pts)
    found_continents = set(analysis.get('continents_found', []))
    missing = expected_continents - found_continents
    if not missing:
        score += 15
        subscores['continents_coverage'] = True
        feedback_parts.append("All expected continents generated")
    else:
        found_count = len(expected_continents) - len(missing)
        partial = int(15 * (found_count / len(expected_continents)))
        score += partial
        subscores['continents_coverage'] = False
        feedback_parts.append(f"Missing continents: {list(missing)[:3]}...")

    # 7. Feature Count Plausibility (10 pts)
    # NE 110m countries usually has ~177 features
    total_features = analysis.get('total_features', 0)
    if 150 <= total_features <= 200:
        score += 10
        subscores['feature_count'] = True
        feedback_parts.append(f"Total feature count plausible ({total_features})")
    else:
        subscores['feature_count'] = False
        feedback_parts.append(f"Total features {total_features} suspicious (expected ~177)")

    passed = score >= 60 and subscores.get('files_exist')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }