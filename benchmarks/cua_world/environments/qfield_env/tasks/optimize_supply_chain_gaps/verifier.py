#!/usr/bin/env python3
"""
Verifier for optimize_supply_chain_gaps task.

Verifies:
1. GeoPackage file modification.
2. New feature creation in 'field_observations'.
3. Correct spatial logic (Midpoint of Lima-Santiago vs Quito-Lima).
4. Attribute correctness.
"""

import json
import os
import sqlite3
import struct
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Helper Functions ---

def parse_gpkg_point(blob):
    """
    Parses a GeoPackage Binary Geometry Point.
    Ref: OGC GeoPackage Encoding Standard
    
    Returns: (x, y) tuple or None if parsing fails/not a point.
    """
    try:
        # Header is at least 8 bytes (Magic 2 + Version 1 + Flags 1 + SRS_ID 4)
        if len(blob) < 8:
            return None
        
        # Check Magic 'GP'
        if blob[0:2] != b'GP':
            return None
            
        version = blob[2]
        flags = blob[3]
        
        # Parse Flags
        # Bit 0: Envelope Geometry Type (0=Standard)
        # Bit 5: Binary Type (0=Standard)
        # Bit 1-3: Envelope Content (0=None, 1=32 bytes, 2=48 bytes, 3=64 bytes, 4=48 bytes)
        
        envelope_indicator = (flags >> 1) & 0x07
        endianness = flags & 0x01 # 0=Big, 1=Little
        
        header_len = 8
        envelope_len = 0
        if envelope_indicator == 1: envelope_len = 32
        elif envelope_indicator == 2: envelope_len = 48
        elif envelope_indicator == 3: envelope_len = 64
        elif envelope_indicator == 4: envelope_len = 48
        
        offset = header_len + envelope_len
        
        if len(blob) < offset + 5: # WKB header (1+4) minimum
            return None
            
        # WKB Parsing
        wkb_bytes = blob[offset:]
        
        # Byte order of WKB
        wkb_endian = wkb_bytes[0] # 0=Big, 1=Little
        endian_char = '<' if wkb_endian == 1 else '>'
        
        # Geometry Type (4 bytes)
        geom_type = struct.unpack(endian_char + 'I', wkb_bytes[1:5])[0]
        
        # Check for Point (Type 1) or PointZ/M variants usually masked
        # Simple Point is 1. wkbPoint = 1
        if geom_type != 1:
            # Could handle 2D Point only for this task
            return None
            
        # Point coordinates (X, Y) - 2 doubles (16 bytes)
        if len(wkb_bytes) < 21:
            return None
            
        x, y = struct.unpack(endian_char + 'dd', wkb_bytes[5:21])
        return (x, y)
        
    except Exception as e:
        logger.error(f"Error parsing blob: {e}")
        return None

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance in km between two lat/lon points."""
    R = 6371  # Earth radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2) * math.sin(dlat/2) + \
        math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * \
        math.sin(dlon/2) * math.sin(dlon/2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

def verify_supply_chain_optimization(traj, env_info, task_info):
    """
    Main verification function.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy capability missing."}

    # 1. Retrieve Artifacts
    temp_json_path = tempfile.mktemp(suffix=".json")
    temp_gpkg_path = tempfile.mktemp(suffix=".gpkg")
    
    try:
        # Pull JSON result
        try:
            copy_from_env("/sdcard/task_result.json", temp_json_path)
            with open(temp_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result JSON: {str(e)}"}
            
        # Pull GeoPackage
        try:
            # We use the staged path from export_result.sh
            copy_from_env("/sdcard/result_world_survey.gpkg", temp_gpkg_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result GeoPackage: {str(e)}"}

        # 2. Check Basic File Stats
        if not result_data.get("gpkg_modified", False):
            return {"passed": False, "score": 0, "feedback": "Project file was not modified. No changes saved."}

        # 3. Analyze GeoPackage Content
        conn = sqlite3.connect(temp_gpkg_path)
        cursor = conn.cursor()
        
        # Defined Coordinates (Ground Truth)
        # Quito (-0.22, -78.51)
        # Lima (-12.04, -77.04)
        # Santiago (-33.44, -70.66)
        
        # Calculate Ground Truth Segments
        dist_ql = haversine_distance(-0.22, -78.51, -12.04, -77.04)
        dist_ls = haversine_distance(-12.04, -77.04, -33.44, -70.66)
        
        # Identify Target Midpoint (Lima-Santiago is longer)
        target_lat = (-12.04 + -33.44) / 2  # -22.74
        target_lon = (-77.04 + -70.66) / 2  # -73.85
        wrong_midpoint_lat = (-0.22 + -12.04) / 2 # -6.13 (Quito-Lima midpoint)
        wrong_midpoint_lon = (-78.51 + -77.04) / 2 # -77.77
        
        # Query New Features
        # field_observations table: look for features added recently or by name
        # We assume original dataset has known count or we filter by attributes
        
        # QField stores geometry in 'geom' column usually
        # Check table schema just in case, but standard is 'geom' or 'geometry'
        try:
            cursor.execute("SELECT name, description, geom FROM field_observations WHERE name LIKE '%Rest_Stop%' OR description LIKE '%Midpoint%'")
            rows = cursor.fetchall()
        except sqlite3.OperationalError:
            return {"passed": False, "score": 0, "feedback": "Could not query 'field_observations' table. Layer may be missing."}

        if not rows:
             return {"passed": False, "score": 20, "feedback": "File modified, but no 'Rest_Stop' feature found in field_observations."}

        best_score = 0
        feedback = []

        for row in rows:
            name = row[0] if row[0] else ""
            desc = row[1] if row[1] else ""
            blob = row[2]
            
            coords = parse_gpkg_point(blob)
            if not coords:
                feedback.append(f"Feature '{name}' has invalid geometry.")
                continue
                
            pt_lon, pt_lat = coords
            
            # Distance from True Target (Lima-Santiago midpoint)
            dist_to_target = haversine_distance(pt_lat, pt_lon, target_lat, target_lon)
            
            # Distance from Wrong Target (Quito-Lima midpoint)
            dist_to_wrong = haversine_distance(pt_lat, pt_lon, wrong_midpoint_lat, wrong_midpoint_lon)
            
            current_score = 0
            
            # Criterion 1: Feature Exists (Base)
            current_score += 20
            
            # Criterion 2: Correct Segment Selection
            if dist_to_target < dist_to_wrong:
                current_score += 40
                segment_correct = True
            else:
                feedback.append("Selected wrong segment (closer to Quito-Lima midpoint).")
                segment_correct = False
                
            # Criterion 3: Positional Accuracy (within ~160km / 1.5 deg)
            if segment_correct and dist_to_target < 160:
                current_score += 30
            elif segment_correct:
                feedback.append(f"Position inaccurate. {dist_to_target:.1f}km from midpoint.")
                
            # Criterion 4: Attributes
            if "Rest_Stop" in name:
                current_score += 5
            if "Midpoint" in desc or "midpoint" in desc.lower():
                current_score += 5
                
            if current_score > best_score:
                best_score = current_score
        
        conn.close()
        
        passed = best_score >= 60
        final_feedback = "Task Complete. " + " ".join(feedback) if feedback else "Perfect execution."
        
        return {
            "passed": passed,
            "score": best_score,
            "feedback": final_feedback
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_json_path): os.remove(temp_json_path)
        if os.path.exists(temp_gpkg_path): os.remove(temp_gpkg_path)