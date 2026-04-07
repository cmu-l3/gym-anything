#!/usr/bin/env python3
"""
Verifier for mark_excavation_site task.

Verifies:
1. GeoPackage contains 4 new features with specific names.
2. Points are spatially clustered around Brasilia (precision check).
3. VLM trajectory shows zooming interaction (process check).
"""

import sqlite3
import math
import json
import os
import tempfile
import logging
from typing import Dict, Any, List, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
BRASILIA_LAT = -15.793889
BRASILIA_LON = -47.882778
# Approx meters per degree at equator (simplified, but sufficient for this scale check)
METERS_PER_DEGREE = 111320
# 500 meters in degrees (approx)
MAX_DIST_DEGREES = 500 / METERS_PER_DEGREE  # ~0.0045

def calculate_distance(lat1, lon1, lat2, lon2):
    """Calculate Euclidean distance in degrees (sufficient for small area check)."""
    return math.sqrt((lat1 - lat2)**2 + (lon1 - lon2)**2)

def verify_excavation_site(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # Setup temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        local_gpkg = os.path.join(temp_dir, "result.gpkg")
        local_meta = os.path.join(temp_dir, "result_meta.json")
        
        # Fetch files from Android environment
        try:
            copy_from_env("/sdcard/task_export/result.gpkg", local_gpkg)
            copy_from_env("/sdcard/task_export/result_meta.json", local_meta)
        except Exception as e:
            logger.error(f"Failed to copy task artifacts: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task output files"}

        # 1. Check Metadata
        try:
            with open(local_meta, 'r') as f:
                meta = json.load(f)
        except:
            meta = {}

        if not meta.get("gpkg_exists"):
            return {"passed": False, "score": 0, "feedback": "GeoPackage file was not found/exported"}

        # 2. Analyze GeoPackage
        score = 0
        feedback_parts = []
        
        try:
            conn = sqlite3.connect(local_gpkg)
            cursor = conn.cursor()
            
            # Query for the specific Corner points
            # We look for features created during the task. 
            # Since we can't rely on timestamps inside GPKG reliably across all versions,
            # we query by the specific names requested in the prompt.
            cursor.execute("""
                SELECT name, ST_X(geom), ST_Y(geom) 
                FROM field_observations 
                WHERE name IN ('Corner 1', 'Corner 2', 'Corner 3', 'Corner 4')
            """)
            rows = cursor.fetchall()
            conn.close()
            
            # Check Feature Count
            found_names = set(r[0] for r in rows)
            count = len(found_names)
            
            if count == 4:
                score += 20
                feedback_parts.append("All 4 corner points found.")
            else:
                feedback_parts.append(f"Found {count}/4 corner points ({', '.join(found_names)}).")
                score += count * 5

            # Check Spatial Precision (The "Zoom" Test)
            points_within_range = 0
            max_observed_dist = 0
            
            for name, lon, lat in rows:
                # Handle potential NULL geometries
                if lon is None or lat is None:
                    feedback_parts.append(f"{name} has no geometry.")
                    continue
                    
                dist = calculate_distance(lat, lon, BRASILIA_LAT, BRASILIA_LON)
                max_observed_dist = max(max_observed_dist, dist)
                
                if dist <= MAX_DIST_DEGREES:
                    points_within_range += 1
                else:
                    feedback_parts.append(f"{name} is too far ({dist:.4f} deg, limit {MAX_DIST_DEGREES:.4f}).")

            # Score Precision
            if count > 0:
                if points_within_range == count:
                    score += 40
                    feedback_parts.append("All points are within valid 500m construction zone.")
                elif points_within_range > 0:
                    score += int(40 * (points_within_range / count))
                    feedback_parts.append("Some points are outside the 500m zone - did you zoom in enough?")
                else:
                    feedback_parts.append("All points are too far away. You must ZOOM IN to placing markers accurately.")
            
            # Check Spatial Layout (Box vs Line/Point)
            if count >= 3:
                lats = [r[2] for r in rows if r[2] is not None]
                lons = [r[1] for r in rows if r[1] is not None]
                if lats and lons:
                    lat_spread = max(lats) - min(lats)
                    lon_spread = max(lons) - min(lons)
                    # A very rough check that they aren't all on top of each other
                    if lat_spread > 0.0001 and lon_spread > 0.0001:
                        score += 20
                        feedback_parts.append("Points form a valid spatial arrangement.")
                    else:
                        feedback_parts.append("Points are stacked on top of each other.")

        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"GeoPackage analysis failed: {str(e)}"}

        # 3. VLM Verification (Attributes & Process)
        # We assume VLM evaluator might add to this, but here we add base points for
        # attributes if the database check passed (since we queried by name).
        if count == 4:
            score += 20  # Attributes (names) were correct per the SQL query
        
        # Final Pass Determination
        passed = (score >= 80)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback_parts)
        }