#!/usr/bin/env python3
"""
Verifier for nile_agricultural_survey task.

VERIFICATION STRATEGY:
This is a complex, long-horizon task requiring multiple deliverables:
  1. CSV import (12 Nile survey stations)
  2. Folder creation ("Nile Corridor Agricultural Survey")
  3. Path drawing ("Nile Main Channel" with 25+ waypoints, Aswan to Luxor)
  4. Two polygon delineations ("East Bank Agriculture", "West Bank Agriculture")
  5. 3D terrain screenshot saved to file
  6. Complete folder exported as KMZ

Verification uses export_result.json data collected by export_result.sh,
plus VLM trajectory analysis. The verifier is intentionally kept as a stub
since vlm_checklist_verifier will be used for primary evaluation.

ANTI-GAMING:
- Timestamp checks on KMZ and screenshot files
- Before/after placemark count comparison
- Station name matching for CSV import
- VLM trajectory verification
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_nile_agricultural_survey(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Verify that the agent completed the Nile corridor agricultural survey.

    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env and query_vlm
        task_info: Task metadata

    Returns:
        dict with 'passed', 'score', 'feedback', 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available for verification",
            "details": {}
        }

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # READ EXPORT RESULTS
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details["export_result"] = result_data
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
        feedback_parts.append("Could not read export results")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # ================================================================
    # CRITERION 1: KMZ file exists and created during task (15 points)
    # ================================================================
    kmz_exists = result_data.get('kmz_exists', False)
    kmz_during_task = result_data.get('kmz_created_during_task', False)
    kmz_size = result_data.get('kmz_size_bytes', 0)

    if kmz_exists and kmz_during_task and kmz_size > 100:
        score += 15
        feedback_parts.append(f"KMZ file exported ({kmz_size} bytes)")
    elif kmz_exists and kmz_size > 100:
        score += 8
        feedback_parts.append("KMZ file exists but may not be from this task")
    elif kmz_exists:
        score += 3
        feedback_parts.append("KMZ file exists but is very small")
    else:
        feedback_parts.append("KMZ file not found")
    details["kmz_check"] = {"exists": kmz_exists, "during_task": kmz_during_task, "size": kmz_size}

    # ================================================================
    # CRITERION 2: Folder structure in KML (5 points)
    # ================================================================
    kml_analysis = result_data.get('kml_analysis', {})
    has_folder = kml_analysis.get('has_folder', False)
    folder_name = kml_analysis.get('folder_name', '')

    if has_folder and 'nile' in folder_name.lower():
        score += 5
        feedback_parts.append(f"Folder found: '{folder_name}'")
    elif has_folder:
        score += 3
        feedback_parts.append(f"Folder found but name mismatch: '{folder_name}'")
    else:
        feedback_parts.append("Target folder not found in KML")
    details["folder_check"] = {"found": has_folder, "name": folder_name}

    # ================================================================
    # CRITERION 3: Path with sufficient vertices (20 points)
    # ================================================================
    has_linestring = kml_analysis.get('has_linestring', False)
    vertex_count = kml_analysis.get('path_vertex_count', 0)
    min_vertices = metadata.get('min_path_vertices', 25)

    if has_linestring and vertex_count >= min_vertices:
        score += 20
        feedback_parts.append(f"Path found with {vertex_count} vertices (required {min_vertices})")
    elif has_linestring and vertex_count >= min_vertices * 0.6:
        score += 12
        feedback_parts.append(f"Path found with {vertex_count} vertices (below {min_vertices} required)")
    elif has_linestring and vertex_count > 0:
        score += 6
        feedback_parts.append(f"Path found with only {vertex_count} vertices")
    elif has_linestring:
        score += 3
        feedback_parts.append("LineString found but vertex count unclear")
    else:
        feedback_parts.append("No path/LineString found")
    details["path_check"] = {"has_linestring": has_linestring, "vertices": vertex_count}

    # ================================================================
    # CRITERION 4: Polygons exist (15 points)
    # ================================================================
    polygon_count = kml_analysis.get('polygon_count', 0)

    if polygon_count >= 2:
        score += 15
        feedback_parts.append(f"{polygon_count} polygons found")
    elif polygon_count == 1:
        score += 8
        feedback_parts.append("Only 1 polygon found (expected 2)")
    else:
        feedback_parts.append("No polygons found")
    details["polygon_check"] = {"count": polygon_count}

    # ================================================================
    # CRITERION 5: CSV import evidence (10 points)
    # ================================================================
    csv_accessed = result_data.get('csv_file_accessed', False)
    station_count = result_data.get('matching_station_count', 0)
    new_placemarks = result_data.get('new_placemarks_added', 0)

    if station_count >= 8:
        score += 10
        feedback_parts.append(f"{station_count} station names found - CSV imported")
    elif station_count >= 4:
        score += 6
        feedback_parts.append(f"{station_count} station names found - partial import")
    elif csv_accessed:
        score += 3
        feedback_parts.append("CSV file accessed but stations not confirmed")
    elif new_placemarks >= 8:
        score += 5
        feedback_parts.append(f"{new_placemarks} new placemarks (likely from CSV)")
    else:
        feedback_parts.append("No evidence of CSV import")
    details["csv_check"] = {
        "accessed": csv_accessed,
        "stations_found": station_count,
        "new_placemarks": new_placemarks
    }

    # ================================================================
    # CRITERION 6: Screenshot file exists (10 points)
    # ================================================================
    ss_exists = result_data.get('screenshot_exists', False)
    ss_during_task = result_data.get('screenshot_created_during_task', False)
    ss_size = result_data.get('screenshot_size_bytes', 0)

    if ss_exists and ss_during_task and ss_size > 10000:
        score += 10
        feedback_parts.append(f"3D screenshot saved ({ss_size} bytes)")
    elif ss_exists and ss_size > 10000:
        score += 5
        feedback_parts.append("Screenshot exists but timing unconfirmed")
    elif ss_exists:
        score += 2
        feedback_parts.append("Screenshot exists but is very small")
    else:
        feedback_parts.append("Screenshot file not found")
    details["screenshot_check"] = {"exists": ss_exists, "during_task": ss_during_task, "size": ss_size}

    # ================================================================
    # CRITERION 7: Google Earth was running (5 points)
    # ================================================================
    ge_running = result_data.get('google_earth_running', False)
    if ge_running:
        score += 5
        feedback_parts.append("Google Earth was running")
    else:
        feedback_parts.append("Google Earth not running")

    # ================================================================
    # CRITERION 8: VLM trajectory verification (20 points) - stub
    # ================================================================
    # VLM verification will be handled by vlm_checklist_verifier
    # Leaving as a stub that awards partial credit if trajectory exists
    vlm_score = 0
    if traj and traj.get('frames'):
        frame_count = len(traj.get('frames', []))
        if frame_count > 50:
            vlm_score = 10
            feedback_parts.append(f"Trajectory recorded ({frame_count} frames)")
        elif frame_count > 10:
            vlm_score = 5
            feedback_parts.append(f"Short trajectory recorded ({frame_count} frames)")
    score += vlm_score
    details["vlm_stub"] = {"score": vlm_score}

    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key criteria: KMZ must exist AND path must exist
    key_criteria_met = kmz_exists and has_linestring
    passed = score >= 60 and key_criteria_met

    score = min(score, 100)

    details["score_breakdown"] = {
        "kmz_file": 15 if (kmz_exists and kmz_during_task and kmz_size > 100) else 0,
        "folder": 5 if (has_folder and 'nile' in folder_name.lower()) else 0,
        "path_vertices": 20 if (has_linestring and vertex_count >= min_vertices) else 0,
        "polygons": 15 if polygon_count >= 2 else 0,
        "csv_import": 10 if station_count >= 8 else 0,
        "screenshot": 10 if (ss_exists and ss_during_task and ss_size > 10000) else 0,
        "ge_running": 5 if ge_running else 0,
        "vlm_trajectory": vlm_score
    }

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
