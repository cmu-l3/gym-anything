#!/usr/bin/env python3
"""
Verifier for add_relay_midpoint task.

Verifies that:
1. A new point feature exists in the GeoPackage.
2. The point is located at the geographic midpoint of Nairobi and Addis Ababa.
3. The feature has the correct name and description.
4. VLM confirms the agent performed the workflow (map navigation, data entry).
"""

import json
import os
import sqlite3
import math
import tempfile
import logging
from typing import Dict, Any, Tuple

# Import VLM utilities if available, otherwise stub
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in km."""
    R = 6371  # Earth radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2) * math.sin(dlat/2) + \
        math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * \
        math.sin(dlon/2) * math.sin(dlon/2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

def get_feature_coords(blob):
    """
    Extract coordinates from a GeoPackage binary blob (WKB/GPKG blob).
    This is a simplified parser for Standard GeoPackageBinary Header.
    """
    # GeoPackageBinary Header is at least 8 bytes.
    # Byte 0-1: Magic 0x47 0x50
    # Byte 2: Version
    # Byte 3: Flags (Binary format 0=Standard, etc)
    # Byte 4-7: SRID
    # ... Envelope ...
    # ... WKB ...
    
    # For point data in QField/QGIS default, it usually works with WKB parsers
    # skipping the header.
    # However, a robust way without shapely/gdal is tricky.
    # We will try to parse the envelope if present, or use a heuristic.
    
    # Heuristic: The coordinates (double) are at the end of the blob for a Point.
    # A Point WKB is 1 byte endian + 4 bytes type + 8 bytes X + 8 bytes Y = 21 bytes.
    # The header is variable.
    
    try:
        import struct
        # Look for the Point WKB signature (Little Endian: 01 01 00 00 00)
        # hex: 0101000000
        hex_blob = blob.hex()
        wkb_start = hex_blob.find("0101000000")
        if wkb_start != -1:
            # Parse X and Y from WKB
            # Start index is in hex chars, so divide by 2 for bytes
            start_byte = wkb_start // 2
            # Skip 1 (order) + 4 (type) = 5 bytes
            # Read 8 bytes X, 8 bytes Y
            data_start = start_byte + 5
            x_bytes = blob[data_start:data_start+8]
            y_bytes = blob[data_start+8:data_start+16]
            x = struct.unpack('<d', x_bytes)[0]
            y = struct.unpack('<d', y_bytes)[0]
            return x, y
    except Exception as e:
        logger.error(f"Error parsing geometry: {e}")
    
    return None, None

def verify_relay_midpoint(traj, env_info, task_info):
    """
    Verification logic for add_relay_midpoint task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    score = 0
    feedback = []
    passed = False

    # Temp files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_gpkg = tempfile.NamedTemporaryFile(delete=False, suffix='.gpkg').name

    try:
        # 1. Retrieve Result JSON and GeoPackage
        try:
            copy_from_env("/sdcard/task_result.json", temp_json)
            with open(temp_json, 'r') as f:
                result_data = json.load(f)
            
            gpkg_path = result_data.get("gpkg_path", "/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg")
            copy_from_env(gpkg_path, temp_gpkg)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}

        # 2. Verify Database Content
        conn = sqlite3.connect(temp_gpkg)
        cursor = conn.cursor()

        # Get Reference Coordinates (Nairobi & Addis Ababa)
        # Assuming table is 'world_capitals' or similar
        try:
            cursor.execute("SELECT name, geom FROM world_capitals WHERE name IN ('Nairobi', 'Addis Ababa')")
            cities = cursor.fetchall()
            
            city_coords = {}
            for name, geom_blob in cities:
                lon, lat = get_feature_coords(geom_blob)
                if lon is not None:
                    city_coords[name] = (lat, lon)
            
            if len(city_coords) != 2:
                # Fallback hardcoded if DB query fails or data missing
                city_coords = {
                    "Nairobi": (-1.286389, 36.817223),
                    "Addis Ababa": (9.024976, 38.74689)
                }
                feedback.append("Using fallback reference coordinates.")
            
            nairobi = city_coords.get("Nairobi")
            addis = city_coords.get("Addis Ababa")
            
            # Expected Midpoint
            expected_lat = (nairobi[0] + addis[0]) / 2
            expected_lon = (nairobi[1] + addis[1]) / 2
            
            feedback.append(f"Expected Midpoint: {expected_lat:.4f}, {expected_lon:.4f}")

        except Exception as e:
            conn.close()
            return {"passed": False, "score": 0, "feedback": f"Error reading reference data: {e}"}

        # Check for New Feature
        # We look for the most recently added feature in field_observations
        cursor.execute("SELECT name, notes, geom FROM field_observations ORDER BY fid DESC LIMIT 1")
        new_feature = cursor.fetchone()
        conn.close()

        if not new_feature:
            feedback.append("No feature found in field_observations.")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

        feat_name, feat_notes, feat_geom = new_feature
        feat_name = feat_name or ""
        feat_notes = feat_notes or ""
        
        # Check Anti-Gaming (Timestamp check was done in shell, verified here)
        final_count = result_data.get("final_count", 0)
        initial_count = result_data.get("initial_count", 0)
        
        if final_count <= initial_count:
            feedback.append("No new features added (count did not increase).")
        else:
            score += 10
            feedback.append("New feature creation detected.")

        # Check Attributes
        if "Relay Tower Alpha".lower() in feat_name.lower():
            score += 15
            feedback.append("Correct feature name.")
        else:
            feedback.append(f"Incorrect name: '{feat_name}'")

        if "Nairobi".lower() in feat_notes.lower() and "Addis Ababa".lower() in feat_notes.lower():
            score += 10
            feedback.append("Description references both cities.")
        elif "Nairobi".lower() in feat_notes.lower() or "Addis Ababa".lower() in feat_notes.lower():
            score += 5
            feedback.append("Description references one city.")
        else:
            feedback.append("Description missing city references.")

        # Check Geometry
        obs_lon, obs_lat = get_feature_coords(feat_geom)
        
        if obs_lon is None or obs_lat is None:
            feedback.append("Could not parse feature geometry.")
        else:
            dist_km = haversine_distance(obs_lat, obs_lon, expected_lat, expected_lon)
            feedback.append(f"Placed at {obs_lat:.4f}, {obs_lon:.4f} (Error: {dist_km:.1f} km)")
            
            if dist_km < 25:  # High precision (~0.2 deg)
                score += 30
                feedback.append("Location is accurate (<25km).")
            elif dist_km < 60:  # Low precision (~0.5 deg)
                score += 15
                feedback.append("Location is acceptable (<60km).")
            else:
                feedback.append("Location is too far from midpoint.")

        # 3. VLM Verification (Trajectory Analysis)
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = (
            "Analyze these screenshots of a QField GIS task. "
            "1. Did the user open a feature form to read coordinates? "
            "2. Did the user navigate to East Africa (Kenya/Ethiopia)? "
            "3. Did the user add a point on the map? "
            "Return JSON: { 'read_coords': bool, 'navigated_africa': bool, 'added_point': bool }"
        )
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_data = vlm_result.get("parsed", {})
        
        if vlm_data.get("navigated_africa"):
            score += 15
            feedback.append("VLM: Navigation verified.")
        if vlm_data.get("read_coords") or vlm_data.get("added_point"):
            score += 20
            feedback.append("VLM: Workflow actions verified.")

        # Final Score Calculation
        passed = score >= 60 and (final_count > initial_count)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_json):
            os.remove(temp_json)
        if os.path.exists(temp_gpkg):
            os.remove(temp_gpkg)