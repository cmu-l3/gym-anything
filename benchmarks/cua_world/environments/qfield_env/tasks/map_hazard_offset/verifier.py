#!/usr/bin/env python3
"""
Verifier for map_hazard_offset task.
Calculates geodesic distance between a reference point (Paris) and agent-created points.
"""

import json
import os
import sqlite3
import math
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine_distance(lat1, lon1, lat2, lon2):
    """
    Calculate the great circle distance between two points 
    on the earth (specified in decimal degrees).
    Returns distance in kilometers.
    """
    # Convert decimal degrees to radians
    lon1, lat1, lon2, lat2 = map(math.radians, [lon1, lat1, lon2, lat2])

    # Haversine formula
    dlon = lon2 - lon1 
    dlat = lat2 - lat1 
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a)) 
    r = 6371 # Radius of earth in kilometers
    return c * r

def calculate_initial_bearing(lat1, lon1, lat2, lon2):
    """
    Calculates the bearing between two points.
    Returns degrees (0-360).
    """
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    
    y = math.sin(lon2 - lon1) * math.cos(lat2)
    x = math.cos(lat1) * math.sin(lat2) - \
        math.sin(lat1) * math.cos(lat2) * math.cos(lon2 - lon1)
    
    bearing = math.atan2(y, x)
    return (math.degrees(bearing) + 360) % 360

def verify_map_hazard_offset(traj, env_info, task_info):
    """
    Verifies that the agent created a point ~45km West of Paris.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_dist = metadata.get('target_distance_km', 45.0)
    target_bearing = metadata.get('target_bearing_deg', 270.0)
    tol_dist = metadata.get('tolerances', {}).get('distance_km', 5.0)
    tol_bearing = metadata.get('tolerances', {}).get('bearing_deg', 10.0)

    # Temporary files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gpkg = tempfile.NamedTemporaryFile(delete=False, suffix='.gpkg')
    temp_json_path = temp_json.name
    temp_gpkg_path = temp_gpkg.name
    temp_json.close()
    temp_gpkg.close()

    try:
        # 1. Fetch result metadata
        try:
            copy_from_env("/sdcard/task_result.json", temp_json_path)
            with open(temp_json_path, 'r') as f:
                result_meta = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result JSON: {e}"}

        if not result_meta.get('gpkg_exists'):
            return {"passed": False, "score": 0, "feedback": "GeoPackage file was not found in export."}

        # 2. Fetch GeoPackage
        try:
            gpkg_remote_path = result_meta.get('gpkg_path_in_container', '/sdcard/task_output.gpkg')
            copy_from_env(gpkg_remote_path, temp_gpkg_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve GeoPackage: {e}"}

        # 3. Analyze Database
        conn = sqlite3.connect(temp_gpkg_path)
        cursor = conn.cursor()
        
        # Get Paris coordinates (Reference)
        try:
            cursor.execute("SELECT name, ST_X(geom), ST_Y(geom) FROM world_capitals WHERE name LIKE 'Paris%' LIMIT 1")
            ref_row = cursor.fetchone()
            if not ref_row:
                # Fallback to metadata if DB lookup fails (unlikely)
                paris_lon = 2.3522
                paris_lat = 48.8566
                logger.warning("Could not find Paris in DB, using fallback coords")
            else:
                paris_lon = ref_row[1]
                paris_lat = ref_row[2]
        except Exception as e:
            conn.close()
            return {"passed": False, "score": 0, "feedback": f"Database query error (reference): {e}"}

        # Get Agent's new features
        # We look for features created during the task or matching the name
        # Since we don't have a reliable created_at timestamp in the schema usually, 
        # we look for the specific name "Hazard Zone Alpha" or high FIDs
        
        candidates = []
        try:
            # Query for features that look like the target
            cursor.execute("SELECT fid, name, notes, ST_X(geom), ST_Y(geom) FROM field_observations")
            rows = cursor.fetchall()
            
            # Simple heuristic: Identify new rows.
            # In the clean dataset, there are 8 observations. FIDs > 8 are likely new.
            # Or filter by name.
            for row in rows:
                fid, name, notes, lon, lat = row
                # Normalize text
                name = str(name) if name else ""
                notes = str(notes) if notes else ""
                
                # Check 1: Name Match
                name_match = "hazard" in name.lower() or "alpha" in name.lower()
                
                # Check 2: FID check (assuming initial count was ~8)
                is_new = fid > 8
                
                if name_match or is_new:
                    candidates.append({
                        "fid": fid,
                        "name": name,
                        "notes": notes,
                        "lat": lat,
                        "lon": lon
                    })
        except Exception as e:
            conn.close()
            return {"passed": False, "score": 0, "feedback": f"Database query error (candidates): {e}"}
            
        conn.close()

        if not candidates:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "No new features found in 'field_observations' layer. Did you save the point?"
            }

        # 4. Evaluate Candidates
        best_score = 0
        best_feedback = ""

        for c in candidates:
            score = 0
            feedback_parts = []
            
            # Distance Check
            dist = haversine_distance(paris_lat, paris_lon, c['lat'], c['lon'])
            dist_diff = abs(dist - target_dist)
            
            # Bearing Check
            bearing = calculate_initial_bearing(paris_lat, paris_lon, c['lat'], c['lon'])
            bearing_diff = abs(bearing - target_bearing)
            # Handle 360 wrap
            if bearing_diff > 180:
                bearing_diff = 360 - bearing_diff

            # --- Scoring Logic ---
            
            # Criterion 1: Feature Creation (20 pts)
            score += 20
            feedback_parts.append(f"Feature created (FID {c['fid']})")

            # Criterion 2: Bearing (20 pts)
            if bearing_diff <= tol_bearing:
                score += 20
                feedback_parts.append(f"Bearing correct ({bearing:.1f}°)")
            elif bearing_diff <= tol_bearing * 2:
                score += 10
                feedback_parts.append(f"Bearing close ({bearing:.1f}°)")
            else:
                feedback_parts.append(f"Wrong bearing ({bearing:.1f}°, expected {target_bearing}°)")

            # Criterion 3: Distance Accuracy (40 pts)
            if dist_diff <= tol_dist:
                score += 40
                feedback_parts.append(f"Distance precise ({dist:.1f} km)")
            elif dist_diff <= tol_dist * 2:
                score += 20
                feedback_parts.append(f"Distance approx ({dist:.1f} km)")
            else:
                feedback_parts.append(f"Wrong distance ({dist:.1f} km, expected {target_dist} km)")

            # Criterion 4: Longitude Logic / Anti-Flat-Earth (10 pts)
            # If they just subtracted 45km as 0.405 deg (flat earth approx at equator),
            # they would be off by ~15km.
            # Real offset needed: ~0.61 deg. Naive offset: ~0.40 deg.
            # If distance is accurate, they likely did the math right.
            if dist_diff <= tol_dist:
                score += 10

            # Criterion 5: Attributes (10 pts)
            if "hazard" in c['name'].lower() and "alpha" in c['name'].lower():
                score += 10
                feedback_parts.append("Name correct")
            
            if score > best_score:
                best_score = score
                best_feedback = ", ".join(feedback_parts)

        # Final Result
        passed = best_score >= 70
        return {
            "passed": passed,
            "score": best_score,
            "feedback": best_feedback
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_json_path):
            os.unlink(temp_json_path)
        if os.path.exists(temp_gpkg_path):
            os.unlink(temp_gpkg_path)