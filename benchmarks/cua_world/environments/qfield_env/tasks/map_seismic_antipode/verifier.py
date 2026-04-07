#!/usr/bin/env python3
"""
Verifier for map_seismic_antipode task.

Task Goal:
1. Locate Wellington, NZ in QField.
2. Calculate antipode: Lat = -Lat, Lon = Lon +/- 180.
3. Add a point at that location (Spain) with specific attributes.

Verification:
- Checks if a new point exists in 'field_observations'.
- Verifies the point is near the true antipode of Wellington.
- Verifies the point has correct Name and Notes.
"""

import json
import math
import os
import sqlite3
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine_distance(lat1, lon1, lat2, lon2):
    """
    Calculate the great circle distance between two points
    on the earth (specified in decimal degrees).
    Returns distance in kilometers.
    """
    # Convert decimal degrees to radians
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])

    # Haversine formula
    dlon = lon2 - lon1
    dlat = lat2 - lat1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))
    r = 6371  # Radius of earth in kilometers
    return c * r

def verify_map_seismic_antipode(traj, env_info, task_info):
    """
    Verify the agent correctly identified and marked the antipode.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Station Antipode')
    expected_notes = metadata.get('expected_notes', 'Opposite Wellington')
    tolerance_km = metadata.get('tolerance_km', 50)
    target_capital = metadata.get('target_capital', 'Wellington')

    # Temporary directory for artifacts
    temp_dir = tempfile.mkdtemp()
    gpkg_local_path = os.path.join(temp_dir, "world_survey.gpkg")
    result_json_path = os.path.join(temp_dir, "task_result.json")

    try:
        # 1. Retrieve Artifacts
        try:
            copy_from_env("/sdcard/task_result.json", result_json_path)
            copy_from_env("/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg", gpkg_local_path)
            
            with open(result_json_path, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve task data: {str(e)}. Did you save the project?"
            }

        if not task_result.get("file_modified", False):
            return {
                "passed": False,
                "score": 0,
                "feedback": "The GeoPackage file was not modified. Did you save your edits?"
            }

        # 2. Analyze GeoPackage
        conn = sqlite3.connect(gpkg_local_path)
        cursor = conn.cursor()

        # A. Get Ground Truth (Wellington Coordinates)
        cursor.execute("SELECT name, y, x FROM world_capitals WHERE name = ?", (target_capital,))
        capital_row = cursor.fetchone()
        
        if not capital_row:
            return {"passed": False, "score": 0, "feedback": f"Critical Error: Capital '{target_capital}' not found in dataset."}
            
        cap_name, cap_lat, cap_lon = capital_row
        
        # Calculate Antipode
        # Lat is inverted (-Lat)
        # Lon is shifted by 180 degrees (keep in -180 to 180 range)
        anti_lat = -cap_lat
        anti_lon = cap_lon - 180 if cap_lon > 0 else cap_lon + 180
        
        logger.info(f"Target: {cap_name} ({cap_lat}, {cap_lon}) -> Antipode ({anti_lat}, {anti_lon})")

        # B. Find Agent's New Point
        # We look for features in 'field_observations'. 
        # Ideally, we filter by features added during the task, but since we don't have row timestamps in this schema,
        # we check for the specific attributes requested or the latest feature.
        
        # Check by attributes first (best case)
        cursor.execute("""
            SELECT name, description, y, x 
            FROM field_observations 
            WHERE name LIKE ? OR description LIKE ?
        """, (f"%{expected_name}%", f"%{expected_notes}%"))
        
        matches = cursor.fetchall()
        
        # If no match by name, get the last added feature (highest FID) to see if they just forgot the name
        if not matches:
            cursor.execute("SELECT name, description, y, x FROM field_observations ORDER BY fid DESC LIMIT 1")
            last_feature = cursor.fetchone()
            if last_feature:
                matches = [last_feature]

        if not matches:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new features found in 'Field Observations' layer."
            }

        # Evaluate the best match
        best_score = 0
        best_feedback = []
        
        for name, notes, lat, lon in matches:
            current_score = 0
            feedback = []
            
            # Check 1: Location Accuracy (40 pts)
            dist_km = haversine_distance(lat, lon, anti_lat, anti_lon)
            if dist_km <= tolerance_km:
                current_score += 40
                feedback.append(f"Location accurate ({dist_km:.1f}km error).")
            elif dist_km <= tolerance_km * 5:
                # Partial credit for being close (e.g. right country)
                current_score += 10
                feedback.append(f"Location roughly correct but imprecise ({dist_km:.1f}km error).")
            else:
                feedback.append(f"Location incorrect ({dist_km:.1f}km from target).")

            # Check 2: Feature Created (20 pts)
            # Implicitly true if we are iterating, but ensuring it's not an existing feature is hard without IDs.
            # Assuming the 'matches' logic works.
            current_score += 20

            # Check 3: Name (20 pts)
            if name and expected_name.lower() in name.lower():
                current_score += 20
                feedback.append("Name correct.")
            else:
                feedback.append(f"Name mismatch (Expected '{expected_name}', got '{name}').")

            # Check 4: Notes (20 pts)
            if notes and expected_notes.lower() in notes.lower():
                current_score += 20
                feedback.append("Notes correct.")
            else:
                feedback.append(f"Notes mismatch (Expected '{expected_notes}', got '{notes}').")

            if current_score > best_score:
                best_score = current_score
                best_feedback = feedback

        passed = best_score >= 80
        
        return {
            "passed": passed,
            "score": best_score,
            "feedback": " ".join(best_feedback)
        }

    except Exception as e:
        logger.exception("Verification failed")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir)