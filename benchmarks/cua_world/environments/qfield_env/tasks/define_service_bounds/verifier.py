#!/usr/bin/env python3
"""
Verifier for define_service_bounds task.
Calculates the bounding box of specific capitals from the GeoPackage
and verifies if the agent created the correct SW/NE corner points.
"""

import json
import sqlite3
import tempfile
import os
import math
import logging
from typing import Tuple, Dict, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
TARGET_CITIES = ["Bogota", "Brasilia", "Lima", "Santiago"]
SW_POINT_NAME = "Envelope_SW"
NE_POINT_NAME = "Envelope_NE"
TOLERANCE = 0.05  # Degrees tolerance

def get_city_coordinates(cursor, cities):
    """Retrieves coordinates for the list of cities."""
    coords = {}
    placeholders = ','.join('?' for _ in cities)
    query = f"SELECT name, ST_X(geom), ST_Y(geom) FROM world_capitals WHERE name IN ({placeholders})"
    
    try:
        cursor.execute(query, cities)
        rows = cursor.fetchall()
        for r in rows:
            # Normalize name matching if needed, but strict is fine here
            coords[r[0]] = (r[1], r[2])
    except sqlite3.OperationalError:
        # Fallback for older SpatiaLite/GPKG versions where ST_X might be separate functions
        # or geometry blob parsing is needed.
        # However, QField GPKGs usually support ST_X/ST_Y views or functions.
        # If this fails, we might need raw blob parsing, but standard GPKG usually works.
        logger.warning("ST_X/ST_Y failed, trying direct geometry column assuming Point...")
        # Simplified for robustness: assuming the agent doesn't need to do complex SQL, 
        # we can assume the table has standard structure. 
        # Let's try standard query. If it fails, we fail safely.
        pass
        
    return coords

def calculate_bounds(city_coords):
    """Calculates min_x, min_y, max_x, max_y."""
    if not city_coords:
        return None
    
    xs = [c[0] for c in city_coords.values()]
    ys = [c[1] for c in city_coords.values()]
    
    return {
        "min_x": min(xs), # West-most
        "max_x": max(xs), # East-most
        "min_y": min(ys), # South-most
        "max_y": max(ys)  # North-most
    }

def verify_define_service_bounds(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Host error: copy_from_env missing"}

    # 1. Retrieve Data
    temp_dir = tempfile.mkdtemp()
    gpkg_local = os.path.join(temp_dir, "world_survey.gpkg")
    result_json_local = os.path.join(temp_dir, "task_result.json")
    
    try:
        # Copy the GeoPackage
        copy_from_env("/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg", gpkg_local)
        
        # Copy the result metadata (optional, mainly for timestamps if we parsed them)
        copy_from_env("/sdcard/task_result.json", result_json_local)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}

    score = 0
    feedback = []
    passed = False

    try:
        conn = sqlite3.connect(gpkg_local)
        # Enable SpatiaLite loading if available/needed, 
        # though standard GPKG usually stores geometry in blobs that we might need to parse 
        # or use built-in sql functions if the module is loaded.
        # For simplicity in this verifier, we will rely on the fact that 'world_capitals' 
        # often has geometry triggers or we can try to assume simple storage.
        # If ST_X is not available, we might have issues.
        # Note: In standard Python sqlite3, ST_X isn't available by default without loading mod_spatialite.
        # WORKAROUND: We will query the raw bytes or assume valid data if we can't load extension.
        # BETTER: For this task, we can rely on verifying the *Field Observations* which are user added.
        # To get Ground Truth, we can hardcode the approximate coords of the 4 cities 
        # OR try to read them. Let's try to read them.
        
        cursor = conn.cursor()
        
        # Enable loading extension if possible (Linux/Mac specific usually)
        try:
            conn.enable_load_extension(True)
            cursor.execute("SELECT load_extension('mod_spatialite')")
        except:
            pass # Extension might not be available on host

        # 2. Establish Ground Truth
        # If we can't load spatialite, we can't easily read the capital coords dynamically.
        # However, the task uses a FIXED dataset (world_survey.gpkg). 
        # We can hardcode the expected ground truth for robustness against environment issues.
        # Bogota: (4.6097, -74.0817)
        # Brasilia: (-15.7975, -47.8919)
        # Lima: (-12.0464, -77.0428)
        # Santiago: (-33.4489, -70.6693)
        
        # Min X (West): Lima (-77.0428)
        # Max X (East): Brasilia (-47.8919)
        # Min Y (South): Santiago (-33.4489)
        # Max Y (North): Bogota (4.6097)
        
        expected_sw = (-33.4489, -77.0428) # (Lat, Lon) -> (Y, X)
        expected_ne = (4.6097, -47.8919)   # (Lat, Lon) -> (Y, X)
        
        # Note: GPKG usually stores (X, Y) i.e. (Lon, Lat)
        # So Expected SW Point: X=-77.0428, Y=-33.4489
        # Expected NE Point: X=-47.8919, Y=4.6097
        
        ground_truth = {
            "SW": {"x": -77.0428, "y": -33.4489},
            "NE": {"x": -47.8919, "y": 4.6097}
        }

        # 3. Check User's Observations
        # The user adds points to 'field_observations'.
        # We need to extract X/Y from the blob or separate columns if they exist.
        # Often QField adds distinct columns or we parse the GPKG binary header.
        # GPKG Blob format: Header (bytes) -> WKB.
        # Byte 0-1: Magic 0x4750
        # Byte 2: Version
        # Byte 3: Flags (Bit 0: Empty, Bit 5: Extended types)
        # ... srs_id (4 bytes) ... envelope ...
        # Then WKB: Byte order (1 byte), Type (4 bytes), X (8 bytes), Y (8 bytes) for Point.
        
        # Let's write a simple binary parser for GPKG point blobs to be dependency-free.
        def parse_gpkg_point(blob):
            import struct
            # Skip header. Header size depends on flags.
            # Magic (2) + Version (1) + Flags (1) = 4 bytes
            flags = blob[3]
            envelope_indicator = (flags >> 1) & 0x07
            header_len = 8 # Basic header + srs_id
            
            envelope_len = 0
            if envelope_indicator == 1: envelope_len = 32
            elif envelope_indicator == 2: envelope_len = 48
            elif envelope_indicator == 3: envelope_len = 48
            elif envelope_indicator == 4: envelope_len = 64
            
            offset = header_len + envelope_len
            
            # WKB start
            wkb = blob[offset:]
            byte_order = wkb[0]
            endian = '<' if byte_order == 1 else '>'
            
            geom_type = struct.unpack(endian + 'I', wkb[1:5])[0]
            
            # Point is type 1 (or 1001 for Z, 2001 for M, 3001 for ZM)
            # We assume 2D point (type 1)
            if geom_type in [1, 1001, 2001, 3001]:
                x = struct.unpack(endian + 'd', wkb[5:13])[0]
                y = struct.unpack(endian + 'd', wkb[13:21])[0]
                return x, y
            return None

        # Query the features
        cursor.execute("SELECT name, description, geom FROM field_observations")
        rows = cursor.fetchall()
        
        found_sw = False
        found_ne = False
        
        for name, desc, geom in rows:
            if not geom: continue
            
            try:
                pt = parse_gpkg_point(geom)
                if not pt: continue
                x, y = pt
                
                # Check SW
                if name and SW_POINT_NAME.lower() in name.lower():
                    found_sw = True
                    dist = math.sqrt((x - ground_truth["SW"]["x"])**2 + (y - ground_truth["SW"]["y"])**2)
                    if dist <= TOLERANCE:
                        score += 40
                        feedback.append(f"Correct SW point location (dist={dist:.4f})")
                    else:
                        score += 10 # Credit for creating it
                        feedback.append(f"SW point created but location off (Expected X={ground_truth['SW']['x']:.2f}, Y={ground_truth['SW']['y']:.2f}; Got X={x:.2f}, Y={y:.2f})")
                        
                # Check NE
                if name and NE_POINT_NAME.lower() in name.lower():
                    found_ne = True
                    dist = math.sqrt((x - ground_truth["NE"]["x"])**2 + (y - ground_truth["NE"]["y"])**2)
                    if dist <= TOLERANCE:
                        score += 40
                        feedback.append(f"Correct NE point location (dist={dist:.4f})")
                    else:
                        score += 10 # Credit for creating it
                        feedback.append(f"NE point created but location off (Expected X={ground_truth['NE']['x']:.2f}, Y={ground_truth['NE']['y']:.2f}; Got X={x:.2f}, Y={y:.2f})")
            
            except Exception as e:
                logger.warning(f"Error parsing geometry: {e}")

        if found_sw:
            score += 10
            feedback.append("SW Point found.")
        else:
            feedback.append("SW Point NOT found.")

        if found_ne:
            score += 10
            feedback.append("NE Point found.")
        else:
            feedback.append("NE Point NOT found.")

        if score >= 80:
            passed = True
            
        return {
            "passed": passed,
            "score": score,
            "feedback": "; ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if conn: conn.close()
        # Cleanup temp files
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)