#!/usr/bin/env python3
"""
Verifier for localize_distress_signal_intersection task.

Verifies that the agent:
1. Created a new point feature.
2. Placed it at the intersection of Madrid's Latitude and Paris's Longitude.
3. Added correct attributes.
"""

import sqlite3
import struct
import math
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_gpkg_point(blob):
    """
    Parses a GeoPackage Binary Geometry Blob to extract Point coordinates.
    Format ref: http://www.geopackage.org/spec/#gpb_format
    
    Structure:
    - Header (variable length)
      - Magic 'GP' (2 bytes)
      - Version (1 byte)
      - Flags (1 byte)
      - SRS_ID (4 bytes)
      - Envelope (0, 32, 48, or 64 bytes depending on flags)
    - WKB Geometry
      - ByteOrder (1 byte)
      - WKBType (4 bytes)
      - X (8 bytes double)
      - Y (8 bytes double)
    """
    try:
        if not blob or len(blob) < 8:
            return None
            
        # 1. Parse Header
        magic = blob[0:2]
        if magic != b'GP':
            return None # Not a GPKG blob
            
        flags = blob[3]
        
        # Envelope contents indicator (bits 1-3 of flags)
        envelope_indicator = (flags >> 1) & 0x07
        envelope_sizes = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}
        envelope_len = envelope_sizes.get(envelope_indicator, 0)
        
        header_len = 8 + envelope_len # 2(GP)+1(Ver)+1(Flag)+4(SRS) + Envelope
        
        # 2. Parse WKB (Standard Well-Known Binary)
        wkb_start = header_len
        wkb = blob[wkb_start:]
        
        byte_order = wkb[0] # 0=Big Endian (XDR), 1=Little Endian (NDR)
        endian_char = '>' if byte_order == 0 else '<'
        
        # WKB Type (4 bytes)
        wkb_type = struct.unpack(f'{endian_char}I', wkb[1:5])[0]
        
        # Check if it's a Point (Type 1) or PointZ/M variants
        # Point=1, PointZ=1001, PointM=2001, PointZM=3001
        is_point = wkb_type in [1, 1001, 2001, 3001]
        
        if is_point:
            x = struct.unpack(f'{endian_char}d', wkb[5:13])[0]
            y = struct.unpack(f'{endian_char}d', wkb[13:21])[0]
            return (x, y) # Lon, Lat
            
        return None
        
    except Exception as e:
        logger.error(f"Error parsing geometry blob: {e}")
        return None

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculates distance in km between two lat/lon points."""
    R = 6371  # Earth radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def verify_localize_distress_signal(traj, env_info, task_info):
    """
    Verification Logic:
    1. Extract the result GeoPackage.
    2. Query 'world_capitals' to get Ground Truth (Madrid Lat, Paris Lon).
    3. Query 'field_observations' to find the agent's new feature.
    4. Validate spatial accuracy and attributes.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Temp files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gpkg = tempfile.NamedTemporaryFile(delete=False, suffix='.gpkg')
    
    try:
        # 1. Retrieve Result JSON
        try:
            copy_from_env("/sdcard/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result_meta = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result metadata."}

        if not result_meta.get("gpkg_exists"):
            return {"passed": False, "score": 0, "feedback": "GeoPackage file was not found/exported."}

        # 2. Retrieve GeoPackage
        try:
            copy_from_env(result_meta["gpkg_path"], temp_gpkg.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve GeoPackage file."}

        # 3. Analyze GeoPackage
        conn = sqlite3.connect(temp_gpkg.name)
        cursor = conn.cursor()

        # A. Get Ground Truth Coordinates
        # We need Madrid's Y (Lat) and Paris's X (Lon)
        # Note: In GeoPackage, 'geom' is the geometry column
        
        try:
            # Get Madrid Geometry
            cursor.execute("SELECT geom FROM world_capitals WHERE name = ?", ("Madrid",))
            madrid_blob = cursor.fetchone()
            if not madrid_blob:
                return {"passed": False, "score": 0, "feedback": "Error: Madrid not found in reference data."}
            madrid_pt = parse_gpkg_point(madrid_blob[0]) # (Lon, Lat)
            target_lat = madrid_pt[1]

            # Get Paris Geometry
            cursor.execute("SELECT geom FROM world_capitals WHERE name = ?", ("Paris",))
            paris_blob = cursor.fetchone()
            if not paris_blob:
                return {"passed": False, "score": 0, "feedback": "Error: Paris not found in reference data."}
            paris_pt = parse_gpkg_point(paris_blob[0]) # (Lon, Lat)
            target_lon = paris_pt[0]
            
            gt_coords = (target_lon, target_lat) # (X, Y)
            logger.info(f"Ground Truth Intersection: Lon {target_lon}, Lat {target_lat}")
            
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error calculating ground truth: {e}"}

        # B. Find Agent's Feature
        # We look for features created AFTER the task start time, or simply the newest one.
        # Since 'fid' autoincrements, we look for high FIDs.
        # Also check name='Distress Signal'
        
        cursor.execute("SELECT fid, name, notes, geom FROM field_observations ORDER BY fid DESC")
        features = cursor.fetchall()
        
        agent_feature = None
        
        # Heuristic: Look for feature with correct name first, else take newest
        for feat in features:
            fid, name, notes, geom = feat
            if name and "Distress" in name:
                agent_feature = feat
                break
        
        if not agent_feature and features:
            # Fallback to newest if name doesn't match
            # But we need to ensure it's actually new. 
            # The base dataset has 8 observations. If fid > 8, it's new.
            if features[0][0] > 8:
                agent_feature = features[0]

        if not agent_feature:
            return {"passed": False, "score": 0, "feedback": "No new feature found in 'field_observations' layer."}

        fid, name, notes, geom_blob = agent_feature
        agent_pt = parse_gpkg_point(geom_blob)
        
        if not agent_pt:
            return {"passed": False, "score": 20, "feedback": "Feature created but geometry is invalid."}

        # 4. Scoring
        score = 20 # Baseline for creating feature
        feedback = []

        # Distance Check
        dist_km = haversine_distance(agent_pt[1], agent_pt[0], target_lat, target_lon)
        feedback.append(f"Distance to target: {dist_km:.2f} km.")

        if dist_km < 10:
            score += 60 # Excellent precision
            feedback.append("Location is very accurate (<10km).")
        elif dist_km < 50:
            score += 40 # Good precision
            feedback.append("Location is acceptable (<50km).")
        elif dist_km < 200:
            score += 10 # Poor precision
            feedback.append("Location is rough (>50km).")
        else:
            feedback.append("Location is incorrect (>200km offset).")

        # Attribute Check
        name_score = 0
        if name and ("Distress" in name or "Signal" in name):
            name_score = 10
            feedback.append("Name attribute correct.")
        
        notes_score = 0
        if notes and ("Madrid" in notes or "Paris" in notes):
            notes_score = 10
            feedback.append("Notes attribute references cities.")
            
        score += name_score + notes_score

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback),
            "details": {
                "ground_truth": gt_coords,
                "agent_coords": agent_pt,
                "distance_km": dist_km,
                "feature_name": name
            }
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification failed with exception: {e}"}
    finally:
        # Cleanup
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_gpkg.name): os.unlink(temp_gpkg.name)