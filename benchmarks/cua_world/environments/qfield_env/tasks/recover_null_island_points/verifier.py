#!/usr/bin/env python3
"""
Verifier for recover_null_island_points task.
Checks if the corrupted capital cities have been moved from (0,0) to their correct locations.
"""

import json
import os
import sqlite3
import shutil
import tempfile
import math
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Target coordinates (Approximate)
TARGETS = {
    "Caracas": {"lat": 10.50, "lon": -66.90},
    "Bogota": {"lat": 4.60, "lon": -74.08},
    "Quito": {"lat": -0.22, "lon": -78.52}
}
TOLERANCE_DEG = 0.5  # ~55km tolerance for manual placement on mobile

def calculate_distance(lat1, lon1, lat2, lon2):
    """Euclidean distance in degrees (sufficient for this scale/check)."""
    return math.sqrt((lat1 - lat2)**2 + (lon1 - lon2)**2)

def verify_recover_null_island(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback = []
    
    # Create temp directory for artifacts
    temp_dir = tempfile.mkdtemp()
    try:
        # 1. Fetch Result JSON
        local_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/sdcard/task_result.json", local_json_path)
            with open(local_json_path, 'r') as f:
                res_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # 2. Fetch GeoPackage
        gpkg_path_env = res_data.get("gpkg_path", "/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg")
        local_gpkg_path = os.path.join(temp_dir, "world_survey.gpkg")
        try:
            copy_from_env(gpkg_path_env, local_gpkg_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve GeoPackage file. Did you save your changes?"}

        # 3. Check file modification
        if res_data.get("file_modified", False):
            score += 10
            feedback.append("File was modified during task (+10).")
        else:
            feedback.append("Warning: File timestamp suggests no changes were saved.")

        # 4. Analyze Database
        try:
            conn = sqlite3.connect(local_gpkg_path)
            # Enable loading extensions if needed, but we can decode WKB manually or use basic SQL if Geom is standard
            # QField/GPKG usually stores standard GPKG blobs.
            # We can use a simple query to get the blob and parse it in Python if ST_X/ST_Y not available in standard python sqlite3
            
            # Helper to parse GPKG Blob (Header + WKB)
            def parse_gpkg_point(blob):
                # Skip header (variable length, usually 8 bytes for standard flags + SRID 4326)
                # Header: Magic(2) + Ver(1) + Flags(1) + SRID(4) + Envelope(0 or 32 or 48 or 64)
                if not blob: return None
                magic = blob[:2]
                if magic != b'GP': return None
                flags = blob[3]
                envelope_indicator = (flags >> 1) & 0x07
                header_len = 8
                if envelope_indicator == 1: header_len += 32
                elif envelope_indicator == 2: header_len += 48
                elif envelope_indicator == 3: header_len += 48
                elif envelope_indicator == 4: header_len += 64
                
                wkb = blob[header_len:]
                # WKB Point: ByteOrder(1) + Type(4) + X(8) + Y(8)
                import struct
                byte_order = wkb[0] # 1 = Little Endian
                endian = '<' if byte_order == 1 else '>'
                geom_type = struct.unpack(endian + 'I', wkb[1:5])[0]
                
                if geom_type == 1: # Point
                    x = struct.unpack(endian + 'd', wkb[5:13])[0]
                    y = struct.unpack(endian + 'd', wkb[13:21])[0]
                    return (x, y)
                return None

            cursor = conn.cursor()
            cursor.execute("SELECT name, geom FROM world_capitals WHERE name IN ('Caracas', 'Bogota', 'Quito')")
            rows = cursor.fetchall()
            
            restored_count = 0
            null_island_count = 0
            
            for name, blob in rows:
                coords = parse_gpkg_point(blob)
                if not coords:
                    feedback.append(f"Could not parse geometry for {name}.")
                    continue
                
                x, y = coords
                target = TARGETS.get(name)
                
                # Check for Null Island
                if abs(x) < 0.001 and abs(y) < 0.001:
                    null_island_count += 1
                    feedback.append(f"{name} is still at Null Island (0,0).")
                    continue
                
                # Check accuracy
                dist = calculate_distance(y, x, target['lat'], target['lon'])
                if dist <= TOLERANCE_DEG:
                    score += 30
                    restored_count += 1
                    feedback.append(f"{name} restored successfully (error: {dist:.4f}°).")
                else:
                    feedback.append(f"{name} moved but too far from target ({target['lat']}, {target['lon']}). Current: ({y:.4f}, {x:.4f}).")

            conn.close()
            
            if null_island_count == 0:
                score += 10 # Bonus for clearing all
                
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Database analysis failed: {str(e)}"}

        # 5. VLM / Screenshot Check (Optional but good for robust scoring)
        # Using basic file check logic as primary.
        
        passed = (restored_count >= 3)
        
        if passed:
            feedback.append("All cities restored correctly!")
        else:
            feedback.append(f"Only {restored_count}/3 cities restored.")

        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    finally:
        shutil.rmtree(temp_dir)