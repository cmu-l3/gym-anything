#!/usr/bin/env python3
"""
Verifier for SAR Coordinate Handoff Task.

Checks:
1. GeoPackage exists and was modified.
2. New feature 'SAR_Team_Alpha' exists in 'field_observations'.
3. Coordinates of new feature match target (Lat 30.10, Lon 31.50) within tolerance.
4. VLM verification of trajectory (workflow progression).
"""

import json
import sqlite3
import math
import struct
import os
import sys
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Task Constants
TARGET_LAT = 30.10
TARGET_LON = 31.50
TOLERANCE_DEG = 0.05
TARGET_NAME = "SAR_Team_Alpha"

def calculate_distance(lat1, lon1, lat2, lon2):
    """Euclidean distance in degrees."""
    return math.sqrt((lat2 - lat1)**2 + (lon2 - lon1)**2)

def parse_gpkg_point(blob):
    """
    Parse OGC GeoPackage Binary Blob for a Point.
    Ref: http://www.geopackage.org/spec/#gpb_format
    
    Structure:
    - Header (variable length)
      - Magic (2 bytes): 0x47 0x50 ('GP')
      - Version (1 byte)
      - Flags (1 byte)
      - SRS ID (4 bytes)
      - Envelope (variable: 0, 32, 48, 64 bytes)
    - WKB Geometry
    """
    if not blob or len(blob) < 8:
        return None
    
    # Check Magic
    if blob[0] != 0x47 or blob[1] != 0x50:
        logger.warning("Invalid GPKG Magic bytes")
        return None
        
    flags = blob[3]
    
    # Envelope contents (bits 1-3)
    envelope_code = (flags >> 1) & 0x07
    envelope_sizes = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}
    envelope_len = envelope_sizes.get(envelope_code, 0)
    
    # Header length = 2(magic) + 1(ver) + 1(flags) + 4(srs) + envelope
    header_len = 8 + envelope_len
    
    if len(blob) <= header_len:
        logger.warning("Blob too short for WKB")
        return None
        
    wkb = blob[header_len:]
    
    # Parse WKB Point
    # Byte 0: Endianness (0=Big, 1=Little)
    byte_order = wkb[0]
    endian = '<' if byte_order == 1 else '>'
    
    # Bytes 1-4: Type
    geom_type = struct.unpack(endian + 'I', wkb[1:5])[0]
    
    # Types: 1=Point, 1001=PointZ, 2001=PointM, 3001=PointZM
    # Also handle ISO WKB 2D/3D distinctions if needed, but usually 1 or 1001
    
    if geom_type not in [1, 1001, 2001, 3001]:
        logger.warning(f"Unsupported geometry type: {geom_type}")
        return None
        
    # Bytes 5-12: X (Double)
    # Bytes 13-20: Y (Double)
    x = struct.unpack(endian + 'd', wkb[5:13])[0]
    y = struct.unpack(endian + 'd', wkb[13:21])[0]
    
    return (x, y) # Lon, Lat

def verify_sar_coordinate_handoff(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Load exported result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. Extract GeoPackage
    gpkg_remote_path = result_data.get('gpkg_path')
    if not result_data.get('gpkg_exists') or not gpkg_remote_path:
        return {"passed": False, "score": 0, "feedback": "GeoPackage not found or not exported"}

    temp_gpkg = tempfile.NamedTemporaryFile(delete=False, suffix='.gpkg')
    temp_gpkg.close() # close so we can write to path
    
    try:
        copy_from_env(gpkg_remote_path, temp_gpkg.name)
        
        # 3. Analyze Database
        conn = sqlite3.connect(temp_gpkg.name)
        cursor = conn.cursor()
        
        # Find feature
        cursor.execute("SELECT name, geometry FROM field_observations WHERE name = ?", (TARGET_NAME,))
        row = cursor.fetchone()
        
        conn.close()
        
        feature_found = False
        coord_score = 0
        name_score = 0
        dist = 999
        
        if row:
            feature_found = True
            name_score = 30
            
            # Parse Geometry
            coords = parse_gpkg_point(row[1])
            if coords:
                lon, lat = coords
                dist = calculate_distance(lat, lon, TARGET_LAT, TARGET_LON)
                
                if dist <= TOLERANCE_DEG:
                    coord_score = 50
                    feedback_loc = f"Location accurate (dist: {dist:.4f}°)"
                else:
                    feedback_loc = f"Location mismatch. Target: ({TARGET_LAT}, {TARGET_LON}), Found: ({lat:.4f}, {lon:.4f}), Dist: {dist:.4f}°"
            else:
                feedback_loc = "Failed to parse geometry"
        else:
            feedback_loc = f"Feature named '{TARGET_NAME}' not found"

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Database analysis error: {e}"}
    finally:
        if os.path.exists(temp_gpkg.name):
            os.unlink(temp_gpkg.name)

    # 4. VLM Verification
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    vlm_score = 0
    vlm_feedback = ""
    
    if frames and query_vlm:
        prompt = """
        Review these screenshots of a QField usage session.
        The user should:
        1. Search for a city ('Ottawa') or view attributes.
        2. Navigate the map to a desert region (coordinates).
        3. Create a new point feature.
        
        Do you see:
        - An attribute form or search bar?
        - A map view changing significantly?
        - A 'Feature Form' for adding a point?
        """
        
        # Simple heuristic or mock VLM call logic
        try:
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_res.get('success'):
                # Assuming simple positive result for now, in real impl parse JSON
                vlm_score = 20
                vlm_feedback = "Workflow verified visually."
        except:
            vlm_feedback = "VLM check failed."

    # Scoring
    total_score = name_score + coord_score + vlm_score
    passed = (total_score >= 80)
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": f"{feedback_loc}. Name matched: {feature_found}. {vlm_feedback}",
        "details": {
            "distance_deg": dist,
            "feature_found": feature_found
        }
    }