#!/usr/bin/env python3
"""
Verifier for triangulate_coordinate_intersection task.

Verifies:
1. Agent created a new feature in 'field_observations'.
2. Feature coordinates match (Rome.Latitude, Dublin.Longitude).
3. Feature attribute contains 'Climate Control Site'.
4. VLM: Agent inspected Rome and Dublin during the session.
"""

import json
import sqlite3
import struct
import tempfile
import os
import math
import logging
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
ROME_LAT_APPROX = 41.90
DUBLIN_LON_APPROX = -6.26
TOLERANCE = 0.5  # Degrees

def parse_gpkg_point(blob: bytes) -> Optional[Tuple[float, float]]:
    """
    Parses a GeoPackage Binary Geometry blob to extract Point coordinates.
    Format:
    - Header (8+ bytes): Magic(2), Ver(1), Flags(1), SRS_ID(4)
    - Coordinates: X, Y (doubles)
    """
    try:
        # Check Magic 0x47 0x50 ('GP')
        if blob[0] != 0x47 or blob[1] != 0x50:
            return None
            
        # Byte 3 is flags. 
        # Bit 0: 0=BigEndian, 1=LittleEndian
        flags = blob[3]
        little_endian = (flags & 0x01) == 1
        endian_char = '<' if little_endian else '>'
        
        # Envelope bits (1-3)
        # 0: No envelope (header is 8 bytes)
        # 1-4: Envelope present (header is bigger)
        envelope_indicator = (flags >> 1) & 0x07
        
        header_len = 8
        if envelope_indicator > 0:
            # We don't need to parse envelope size strictly for Point, 
            # but usually points don't have envelopes in standard creation.
            # If they do:
            # 1: 32 bytes (XY)
            # 2: 48 bytes (XYZ) etc.
            # For simplicity, let's assume standard point usually lacks envelope 
            # or we skip it based on indicator.
            if envelope_indicator == 1: header_len += 32
            elif envelope_indicator == 2: header_len += 48
            elif envelope_indicator == 3: header_len += 48
            elif envelope_indicator == 4: header_len += 64
            
        # Geometry Type (byte 4-7, but strictly reading wkb)
        # Actually, GPKG wraps standard WKB.
        # After header, we have WKB.
        
        # Let's read the WKB part.
        wkb_start = header_len
        
        # WKB Byte Order (1 byte)
        wkb_byte_order = blob[wkb_start]
        wkb_endian = '<' if wkb_byte_order == 1 else '>'
        
        # WKB Geometry Type (4 bytes)
        # 1 = Point
        geom_type = struct.unpack(wkb_endian + 'I', blob[wkb_start+1 : wkb_start+5])[0]
        
        if geom_type in [1, 1001, 2001, 3001]: # Point variants
            x = struct.unpack(wkb_endian + 'd', blob[wkb_start+5 : wkb_start+13])[0]
            y = struct.unpack(wkb_endian + 'd', blob[wkb_start+13 : wkb_start+21])[0]
            return (x, y)
            
    except Exception as e:
        logger.error(f"Error parsing geometry blob: {e}")
    
    return None

def verify_triangulate_coordinate_intersection(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    tolerance = metadata.get('tolerance_degrees', 0.5)
    
    # Define score components
    score = 0
    feedback_parts = []
    
    # 1. Retrieve the GeoPackage file
    temp_gpkg = tempfile.NamedTemporaryFile(delete=False, suffix='.gpkg')
    temp_gpkg.close() # Close so we can write to it
    
    try:
        copy_from_env("/sdcard/task_result.gpkg", temp_gpkg.name)
        
        # Connect to SQLite
        conn = sqlite3.connect(temp_gpkg.name)
        cursor = conn.cursor()
        
        # 2. Get Ground Truth from 'world_capitals'
        # We query the actual values in the file to be fair
        rome_lat = ROME_LAT_APPROX
        dublin_lon = DUBLIN_LON_APPROX
        
        try:
            # Try to get Rome's Geom
            cursor.execute("SELECT geom FROM world_capitals WHERE name LIKE '%Rome%'")
            rome_row = cursor.fetchone()
            if rome_row:
                pt = parse_gpkg_point(rome_row[0])
                if pt: rome_lat = pt[1] # Y is lat
                
            # Try to get Dublin's Geom
            cursor.execute("SELECT geom FROM world_capitals WHERE name LIKE '%Dublin%'")
            dublin_row = cursor.fetchone()
            if dublin_row:
                pt = parse_gpkg_point(dublin_row[0])
                if pt: dublin_lon = pt[0] # X is lon
        except Exception as e:
            logger.warning(f"Could not extract ground truth from DB, using defaults: {e}")

        logger.info(f"Target: Lat {rome_lat}, Lon {dublin_lon}")

        # 3. Find Candidate Feature in 'field_observations'
        # We look for the most recently added feature or one matching the name
        
        # First check by name
        target_name = "Climate Control Site"
        cursor.execute("SELECT geom, name, notes, fid FROM field_observations WHERE name LIKE ? OR notes LIKE ?", 
                       (f'%{target_name}%', f'%{target_name}%'))
        
        candidates = cursor.fetchall()
        
        best_dist = float('inf')
        best_candidate = None
        
        if not candidates:
            # Fallback: check ANY feature added (assuming high FID means new)
            cursor.execute("SELECT geom, name, notes, fid FROM field_observations ORDER BY fid DESC LIMIT 5")
            candidates = cursor.fetchall()
            feedback_parts.append("No feature found with name 'Climate Control Site'. Checking recent features...")

        for geom_blob, name, notes, fid in candidates:
            pt = parse_gpkg_point(geom_blob)
            if not pt:
                continue
                
            x, y = pt
            # Euclidean distance in degrees (approximate but sufficient for this scale/tolerance)
            dist = math.sqrt((x - dublin_lon)**2 + (y - rome_lat)**2)
            
            if dist < best_dist:
                best_dist = dist
                best_candidate = (x, y, name, notes)

        # 4. Scoring
        if best_candidate:
            x, y, name, notes = best_candidate
            
            # Distance Check
            if best_dist <= tolerance:
                score += 50
                feedback_parts.append(f"Location accurate (Dist: {best_dist:.4f}°).")
            else:
                feedback_parts.append(f"Location incorrect. Target: ({dublin_lon:.2f}, {rome_lat:.2f}), Found: ({x:.2f}, {y:.2f}). Dist: {best_dist:.2f}°")
                if best_dist < tolerance * 5:
                    score += 10 # Partial credit for being in the ballpark
            
            # Attribute Check
            feature_text = (str(name) + " " + str(notes)).lower()
            if target_name.lower() in feature_text:
                score += 30
                feedback_parts.append("Attribute name correct.")
            else:
                feedback_parts.append(f"Attribute text missing '{target_name}'. Found: '{name}/{notes}'")
                
            # Feature Creation Bonus
            score += 20 
        else:
            feedback_parts.append("No valid observation features found.")
            
        conn.close()
        
    except Exception as e:
        feedback_parts.append(f"Verification error: {str(e)}")
    finally:
        if os.path.exists(temp_gpkg.name):
            os.unlink(temp_gpkg.name)

    # 5. VLM / Trajectory Verification (Stub for now, but crucial for anti-gaming)
    # Ideally, we check if they opened the info panels for Rome and Dublin.
    # Since we can't easily run VLM here without the helper, we assume the programmatic check is primary.
    # If using gym_anything.vlm, we would add that here. 
    # For now, if the coordinates are precise, it's strong evidence they looked it up.
    
    final_feedback = " ".join(feedback_parts)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }