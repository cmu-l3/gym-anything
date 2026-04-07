#!/usr/bin/env python3
"""
Verifier for Giza Plateau Archaeological Survey task.

STUB VERIFIER - primary evaluation via vlm_checklist_verifier.

Basic programmatic checks:
1. KML file exists and was created during task
2. KML contains expected folder and placemark names
3. Screenshot file exists
4. Terrain exaggeration set correctly
5. CSV file was accessed (import evidence)
6. New placemarks added to My Places

Full scoring is handled by vlm_checklist.json via the VLM checklist verifier.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected placemark name substrings (case-insensitive matching)
EXPECTED_NAMES = ["khufu", "khafre", "menkaure", "sphinx", "valley temple"]
EXPECTED_FOLDER_SUBSTRING = "giza"


def verify_giza_plateau_survey(traj, env_info, task_info):
    """
    Verify that the Giza Plateau survey was completed.

    Reads the JSON result produced by export_result.sh and checks
    basic file existence, content signals, and anti-gaming timestamps.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    result_details = {}

    # ================================================================
    # Read result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    result_details['task_result'] = result
    kml_data = result.get('kml', {})
    png_data = result.get('screenshot', {})
    myplaces_data = result.get('myplaces', {})
    terrain_data = result.get('terrain', {})

    # ================================================================
    # CRITERION 1: KML file exists (15 points)
    # ================================================================
    kml_exists = kml_data.get('exists', False)
    kml_size = kml_data.get('size_bytes', 0)
    kml_created = kml_data.get('created_during_task', False)

    if kml_exists and kml_size > 200 and kml_created:
        score += 15
        feedback_parts.append(f"KML file exists and created during task ({kml_size} bytes)")
    elif kml_exists and kml_size > 200:
        score += 8
        feedback_parts.append("KML file exists but timestamp not verified")
    elif kml_exists:
        score += 3
        feedback_parts.append("KML file exists but very small")
    else:
        feedback_parts.append("KML file NOT found")

    result_details['kml_exists'] = kml_exists

    # ================================================================
    # CRITERION 2: KML has Giza folder (10 points)
    # ================================================================
    has_folder = kml_data.get('has_giza_folder', False)
    folder_name = kml_data.get('folder_name', '')

    if has_folder:
        score += 10
        feedback_parts.append(f"Giza folder found: '{folder_name}'")
    else:
        feedback_parts.append("Giza folder NOT found in KML")

    # ================================================================
    # CRITERION 3: Placemark names in KML (20 points)
    # ================================================================
    names_str = kml_data.get('placemark_names', '').lower()
    found_names = []
    for name in EXPECTED_NAMES:
        if name in names_str:
            found_names.append(name)

    name_score = min(20, len(found_names) * 4)
    score += name_score
    feedback_parts.append(f"Found {len(found_names)}/{len(EXPECTED_NAMES)} expected placemarks: {found_names}")
    result_details['found_placemarks'] = found_names

    # ================================================================
    # CRITERION 4: Path exists in KML (10 points)
    # ================================================================
    path_count = kml_data.get('path_count', 0)
    has_causeway = "causeway" in names_str

    if path_count > 0 and has_causeway:
        score += 10
        feedback_parts.append(f"Causeway path found ({path_count} path(s) in KML)")
    elif path_count > 0:
        score += 5
        feedback_parts.append(f"Path found but no 'causeway' name ({path_count} path(s))")
    else:
        feedback_parts.append("No path/LineString found in KML")

    # ================================================================
    # CRITERION 5: Screenshot exists (10 points)
    # ================================================================
    png_exists = png_data.get('exists', False)
    png_size = png_data.get('size_bytes', 0)
    png_created = png_data.get('created_during_task', False)

    if png_exists and png_size > 50000 and png_created:
        score += 10
        feedback_parts.append(f"Screenshot saved ({png_size / 1024:.1f}KB)")
    elif png_exists and png_size > 10000:
        score += 5
        feedback_parts.append(f"Screenshot exists but small or pre-existing ({png_size / 1024:.1f}KB)")
    else:
        feedback_parts.append("Screenshot NOT found or too small")

    result_details['screenshot_valid'] = png_exists and png_size > 50000

    # ================================================================
    # CRITERION 6: Terrain exaggeration set (10 points)
    # ================================================================
    exag_found = terrain_data.get('exaggeration_found', False)
    exag_value = terrain_data.get('exaggeration_value', 'unknown')

    if exag_found:
        try:
            exag_float = float(exag_value)
            if abs(exag_float - 2.0) <= 0.3:
                score += 10
                feedback_parts.append(f"Terrain exaggeration correctly set to {exag_value}")
            else:
                score += 3
                feedback_parts.append(f"Terrain exaggeration set to {exag_value} (expected ~2.0)")
        except (ValueError, TypeError):
            feedback_parts.append(f"Terrain exaggeration found but unparseable: {exag_value}")
    else:
        feedback_parts.append("Terrain exaggeration setting not found in config")

    # ================================================================
    # CRITERION 7: CSV file accessed (5 points)
    # ================================================================
    csv_accessed = result.get('csv_file_accessed', False)

    if csv_accessed:
        score += 5
        feedback_parts.append("CSV file accessed (import evidence)")
    else:
        feedback_parts.append("CSV file NOT accessed")

    # ================================================================
    # CRITERION 8: My Places content (20 points)
    # ================================================================
    myplaces_modified = myplaces_data.get('modified', False)
    new_placemarks = myplaces_data.get('new_placemarks_added', 0)
    mp_has_khufu = myplaces_data.get('has_khufu', False)
    mp_has_khafre = myplaces_data.get('has_khafre', False)
    mp_has_menkaure = myplaces_data.get('has_menkaure', False)
    mp_has_sphinx = myplaces_data.get('has_sphinx', False)
    mp_has_causeway = myplaces_data.get('has_causeway', False)

    mp_content_count = sum([mp_has_khufu, mp_has_khafre, mp_has_menkaure, mp_has_sphinx, mp_has_causeway])

    if myplaces_modified and new_placemarks >= 3 and mp_content_count >= 3:
        score += 20
        feedback_parts.append(f"My Places has {new_placemarks} new placemarks, {mp_content_count}/5 expected names")
    elif myplaces_modified and new_placemarks >= 1:
        score += 10
        feedback_parts.append(f"My Places modified with {new_placemarks} new placemarks, {mp_content_count}/5 names")
    elif myplaces_modified:
        score += 5
        feedback_parts.append("My Places modified but no new placemarks detected")
    else:
        feedback_parts.append("My Places NOT modified during task")

    result_details['myplaces_content_count'] = mp_content_count

    # ================================================================
    # Final result
    # ================================================================
    max_score = 100
    passed = score >= 50 and kml_exists and len(found_names) >= 2

    feedback_parts.append(f"\nTotal: {score}/{max_score}")
    feedback_parts.append(f"Result: {'PASS' if passed else 'FAIL'}")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details
    }
