#!/usr/bin/env python3
"""
Verifier for plan_capital_relocation task.

Verifies:
1. Agent added a point named 'Jakarta_Old' near Jakarta.
2. Agent added a point named 'Nusantara_New' on Borneo.
3. Correct attributes ('Decommissioned', 'Proposed') were set.
4. GeoPackage was actually modified during the task.
"""

import sqlite3
import struct
import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_gpkg_point(blob):
    """
    Parse a GeoPackage Binary Geometry blob to extract Point coordinates.
    Format: Header (magic, version, flags, srid) + WKB
    """
    try:
        # Header is at least 8 bytes.
        # Byte 0-1: Magic 0x47 0x50 ('GP')
        # Byte 2: Version
        # Byte 3: Flags
        # Byte 4-7: SRID (int32 little endian)
        
        if len(blob) < 8:
            return None
            
        magic = blob[0:2]
        if magic != b'GP':
            return None
            
        flags = blob[3]
        # envelope_indicator is bits 1-3 of flags
        envelope_indicator = (flags >> 1) & 0x07
        
        header_len = 8
        if envelope_indicator == 1:
            header_len += 32 # 4 doubles
        elif envelope_indicator == 2 or envelope_indicator == 3:
            header_len += 48 # 6 doubles
        elif envelope_indicator == 4:
            header_len += 64 # 8 doubles
            
        wkb_bytes = blob[header_len:]
        
        # Parse WKB Point (assuming Little Endian for simplicity, though strictly should check byte 0)
        # Byte 0: Byte order (1=Little Endian)
        # Byte 1-4: Type (1=Point)
        # Byte 5-12: X
        # Byte 13-20: Y
        
        byte_order = wkb_bytes[0]
        endian = '<' if byte_order == 1 else '>'
        
        geom_type = struct.unpack(f'{endian}I', wkb_bytes[1:5])[0]
        
        # Handle 2D Point (Type 1) or Z/M variants usually not used here
        if geom_type == 1: # Point
            x, y = struct.unpack(f'{endian}dd', wkb_bytes[5:21])
            return (x, y)
            
        return None
    except Exception as e:
        logger.error(f"Error parsing geometry: {e}")
        return None

def verify_plan_capital_relocation(traj, env_info, task_info):
    """
    Verify the capital relocation task.
    """
    # 1. Setup access to files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Create temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        json_path = os.path.join(temp_dir, "task_result.json")
        gpkg_path = os.path.join(temp_dir, "world_survey_final.gpkg")
        
        # 2. Retrieve JSON result
        try:
            # The export script writes to /sdcard/task_results/task_result.json
            copy_from_env("/sdcard/task_results/task_result.json", json_path)
            with open(json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

        if not result_data.get("gpkg_exists"):
            return {"passed": False, "score": 0, "feedback": "No GeoPackage found. Did you save your work?"}
            
        if not result_data.get("modified_during_task"):
            # If the file wasn't modified, the agent did nothing useful
            return {"passed": False, "score": 0, "feedback": "The project file was not modified. Ensure you saved your edits."}

        # 3. Retrieve GeoPackage
        try:
            copy_from_env(result_data["gpkg_path"], gpkg_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve GeoPackage: {str(e)}"}

        # 4. Verify Content via SQLite
        score = 0
        feedback = []
        
        try:
            conn = sqlite3.connect(gpkg_path)
            cursor = conn.cursor()
            
            # Query relevant fields from field_observations
            # We look for features created during the session
            # Note: We query ALL rows because we don't know the exact IDs
            cursor.execute("SELECT name, notes, geom FROM field_observations")
            rows = cursor.fetchall()
            conn.close()
            
            jakarta_found = False
            jakarta_correct_attrs = False
            jakarta_correct_loc = False
            
            nusantara_found = False
            nusantara_correct_attrs = False
            nusantara_correct_loc = False
            
            # Metadata targets
            jak_target = metadata.get("jakarta_target", {"lat": -6.2, "lon": 106.8, "tolerance_deg": 0.5})
            nus_target = metadata.get("nusantara_target", {"lat_min": -2.5, "lat_max": 2.5, "lon_min": 114.0, "lon_max": 119.0})

            for name, notes, geom_blob in rows:
                if not name: continue
                name_clean = name.strip()
                notes_clean = (notes or "").lower()
                
                # Check Jakarta
                if "jakarta_old" in name_clean.lower():
                    jakarta_found = True
                    if "decommissioned" in notes_clean:
                        jakarta_correct_attrs = True
                    
                    coords = parse_gpkg_point(geom_blob)
                    if coords:
                        lon, lat = coords
                        dist = math.sqrt((lon - jak_target['lon'])**2 + (lat - jak_target['lat'])**2)
                        if dist < jak_target['tolerance_deg']:
                            jakarta_correct_loc = True
                
                # Check Nusantara
                if "nusantara_new" in name_clean.lower():
                    nusantara_found = True
                    if "proposed" in notes_clean:
                        nusantara_correct_attrs = True
                        
                    coords = parse_gpkg_point(geom_blob)
                    if coords:
                        lon, lat = coords
                        # Bounding box check for Borneo
                        if (nus_target['lon_min'] <= lon <= nus_target['lon_max'] and 
                            nus_target['lat_min'] <= lat <= nus_target['lat_max']):
                            nusantara_correct_loc = True

            # Scoring Logic
            if jakarta_found:
                score += 30
                feedback.append("Created 'Jakarta_Old' point.")
                if jakarta_correct_loc:
                    score += 20
                    feedback.append("Jakarta location correct.")
                else:
                    feedback.append("Jakarta location incorrect.")
                if jakarta_correct_attrs:
                    score += 10
                    feedback.append("Jakarta attributes correct.")
            else:
                feedback.append("Missing 'Jakarta_Old' point.")

            if nusantara_found:
                score += 20
                feedback.append("Created 'Nusantara_New' point.")
                if nusantara_correct_loc:
                    score += 10
                    feedback.append("Nusantara location correct (on Borneo).")
                else:
                    feedback.append("Nusantara location incorrect.")
                if nusantara_correct_attrs:
                    score += 10
                    feedback.append("Nusantara attributes correct.")
            else:
                feedback.append("Missing 'Nusantara_New' point.")

            passed = (score >= 70)
            
            return {
                "passed": passed,
                "score": score,
                "feedback": " ".join(feedback)
            }

        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}