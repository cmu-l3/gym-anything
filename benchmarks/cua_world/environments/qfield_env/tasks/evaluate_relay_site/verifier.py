#!/usr/bin/env python3
"""
Verifier for evaluate_relay_site task.

Verifies that the agent:
1. Identified Nairobi as the closest capital to the equator.
2. Created a new point in the 'field_observations' layer.
3. Placed the point near Nairobi.
4. Added correct metadata (Name and Description).
"""

import json
import os
import sqlite3
import tempfile
import logging
import math
from typing import Dict, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Target: Nairobi, Kenya
TARGET_LAT = -1.2921
TARGET_LON = 36.8219
# Tolerance in degrees (approx 100km radius is generous enough for manual placement on a global map)
POS_TOLERANCE = 1.0 

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points on Earth in km."""
    R = 6371  # Earth radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2) * math.sin(dlat/2) + \
        math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * \
        math.sin(dlon/2) * math.sin(dlon/2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

def verify_evaluate_relay_site(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the relay site selection task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    gpkg_path = metadata.get('gpkg_path', "/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg")
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON and GeoPackage
    temp_dir = tempfile.mkdtemp()
    local_json = os.path.join(temp_dir, "task_result.json")
    local_gpkg = os.path.join(temp_dir, "world_survey.gpkg")
    
    try:
        # Get JSON
        copy_from_env("/sdcard/task_result.json", local_json)
        with open(local_json, 'r') as f:
            result_data = json.load(f)
            
        # Get GeoPackage
        copy_from_env(gpkg_path, local_gpkg)
        
        # Check if file was modified
        if result_data.get("file_modified", False):
            score += 10
            feedback_parts.append("GeoPackage modified during task (+10)")
        else:
            feedback_parts.append("Warning: GeoPackage timestamp indicates no changes")

        # 2. Analyze GeoPackage Content
        if not os.path.exists(local_gpkg):
            return {"passed": False, "score": score, "feedback": "Failed to retrieve GeoPackage"}

        conn = sqlite3.connect(local_gpkg)
        cursor = conn.cursor()
        
        # Check if 'field_observations' table exists
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='field_observations'")
        if not cursor.fetchone():
            conn.close()
            return {"passed": False, "score": score, "feedback": "Layer 'field_observations' not found in GeoPackage"}

        # Query for the new feature
        # We look for features created/named 'Relay_Uplink_Africa' or similar
        query = """
            SELECT name, description, AsText(geom) 
            FROM field_observations 
            WHERE name LIKE '%Relay%' OR description LIKE '%Nairobi%' OR description LIKE '%Equator%'
        """
        cursor.execute(query)
        rows = cursor.fetchall()
        
        if not rows:
            # Fallback: check last added feature if they messed up the name
            # Assuming fid is autoincrement
            cursor.execute("SELECT name, description, AsText(geom) FROM field_observations ORDER BY fid DESC LIMIT 1")
            rows = cursor.fetchall()
            feedback_parts.append("No feature named 'Relay_Uplink_Africa' found, checking last created feature.")

        target_found = False
        correct_location = False
        attributes_correct = False
        
        for row in rows:
            name, description, geom_wkt = row
            # Handle potential None values
            name = name or ""
            description = description or ""
            geom_wkt = geom_wkt or ""
            
            # Extract coordinates from WKT (POINT(lon lat))
            # e.g., POINT(36.82 -1.29)
            try:
                coords_text = geom_wkt.replace("POINT", "").replace("(", "").replace(")", "").strip()
                parts = coords_text.split()
                if len(parts) >= 2:
                    lon = float(parts[0])
                    lat = float(parts[1])
                    
                    # Verify Location (Nairobi)
                    # Simple euclidian distance on lat/lon is fine for this scale check
                    dist_sq = (lat - TARGET_LAT)**2 + (lon - TARGET_LON)**2
                    if dist_sq < POS_TOLERANCE**2:
                        correct_location = True
                        
            except Exception as e:
                logger.warning(f"Failed to parse geometry: {geom_wkt} - {e}")
                continue

            # Verify Attributes
            if "Relay_Uplink_Africa" in name:
                target_found = True
            
            desc_lower = description.lower()
            if "nairobi" in desc_lower and any(x in desc_lower for x in ["lat", "equator", "1.2", "1.3"]):
                attributes_correct = True
            
            if target_found and correct_location:
                break
        
        conn.close()

        # Scoring
        if target_found:
            score += 25
            feedback_parts.append("Correct feature name created (+25)")
        else:
            feedback_parts.append("Feature name 'Relay_Uplink_Africa' missing")
            
        if correct_location:
            score += 40
            feedback_parts.append("Feature placed at correct city (Nairobi) (+40)")
        else:
            feedback_parts.append("Feature NOT placed at Nairobi (closest to equator)")
            
        if attributes_correct:
            score += 25
            feedback_parts.append("Description contains rationale/coordinates (+25)")
        else:
            feedback_parts.append("Description missing city name or latitude info")

        # 3. VLM Verification (Trajectory)
        # We assume the agent should have inspected multiple points
        # This is a stub for the VLM part, usually handled by a separate function or integrated here
        # If we had VLM results passed in `task_info` or `traj`, we would add points.
        # Since this is a standalone verifier, we trust the file evidence primarily.
        
        passed = (score >= 75) and correct_location
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "; ".join(feedback_parts)
        }

    except Exception as e:
        import traceback
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed with error: {str(e)}\n{traceback.format_exc()}"
        }
    finally:
        # Cleanup
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)