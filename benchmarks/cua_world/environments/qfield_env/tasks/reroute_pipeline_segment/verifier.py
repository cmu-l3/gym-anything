#!/usr/bin/env python3
"""
Verifier for reroute_pipeline_segment task.

Checks if the agent has:
1. Added the pipelines layer (implied by editing it).
2. Edited the 'Cairo-Baghdad' line.
3. Added a vertex at Amman, Jordan.

The verification parses the GeoPackage geometry blob directly.
"""

import json
import tempfile
import os
import struct
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Task constants
AMMAN_LON = 35.93
AMMAN_LAT = 31.95
TOLERANCE = 0.5  # Degrees (~55km, generous for finger tapping)

def parse_gpkg_linestring(blob):
    """
    Parses a GPKG geometry blob containing a LineString.
    Returns a list of (lon, lat) tuples.
    """
    try:
        # 1. Header Analysis
        # Byte 0-1: Magic 0x47 0x50 ('GP')
        if blob[0:2] != b'GP':
            return None
        
        # Byte 3: Flags
        flags = blob[3]
        # Binary flags: 
        # Bit 0: Empty (should be 0)
        # Bit 1-3: Envelope indicator (0=None, 1=32bytes, 2=48bytes, etc)
        # Bit 5: Extended Type (0=Standard WKB)
        
        envelope_indicator = (flags >> 1) & 0x07
        header_len = 8 # Base header size
        
        if envelope_indicator == 1:
            header_len += 32
        elif envelope_indicator == 2:
            header_len += 48
        elif envelope_indicator == 3:
            header_len += 48
        elif envelope_indicator == 4:
            header_len += 64
            
        wkb = blob[header_len:]
        
        # 2. WKB Parsing
        # Byte 0: Byte Order (1=Little Endian)
        byte_order = wkb[0]
        endian = '<' if byte_order == 1 else '>'
        
        # Byte 1-4: Geometry Type (2 = LineString)
        geom_type = struct.unpack(endian + 'I', wkb[1:5])[0]
        
        if geom_type != 2: # Not a LineString
            return None
            
        # Byte 5-8: Num Points
        num_points = struct.unpack(endian + 'I', wkb[5:9])[0]
        
        points = []
        offset = 9
        for _ in range(num_points):
            # Each point is 2 doubles (16 bytes)
            x, y = struct.unpack(endian + 'dd', wkb[offset:offset+16])
            points.append((x, y))
            offset += 16
            
        return points
        
    except Exception as e:
        logger.error(f"Error parsing blob: {e}")
        return None

def verify_reroute_pipeline(traj, env_info, task_info):
    """
    Verifies that the pipeline was rerouted through Amman.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback_parts = []
    passed = False

    # Paths (Android paths mapped to what we pull)
    # The setup script puts files in /sdcard/tasks/reroute_pipeline_segment/
    # We need to pull them.
    
    # Create temp files
    temp_gpkg = tempfile.NamedTemporaryFile(delete=False, suffix='.gpkg')
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # 1. Pull Result JSON
        try:
            copy_from_env("/sdcard/tasks/reroute_pipeline_segment/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                res_json = json.load(f)
                if res_json.get('app_running'):
                    score += 10
                    feedback_parts.append("QField was running.")
        except Exception:
            feedback_parts.append("Could not retrieve task status.")

        # 2. Pull GeoPackage
        try:
            copy_from_env("/sdcard/tasks/reroute_pipeline_segment/result.gpkg", temp_gpkg.name)
        except Exception:
            return {"passed": False, "score": score, "feedback": "Failed to retrieve GeoPackage."}

        # 3. Analyze GeoPackage
        import sqlite3
        conn = sqlite3.connect(temp_gpkg.name)
        cursor = conn.cursor()
        
        # Check table exists
        try:
            cursor.execute("SELECT name, geom FROM pipelines WHERE name='Cairo-Baghdad'")
            row = cursor.fetchone()
        except sqlite3.Error:
            row = None
            
        if not row:
            feedback_parts.append("Pipeline feature 'Cairo-Baghdad' not found or table missing.")
            return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}
            
        name, blob = row
        score += 10 # Feature exists
        
        # Parse Geometry
        points = parse_gpkg_linestring(blob)
        
        if not points:
            feedback_parts.append("Invalid geometry format.")
        else:
            n_points = len(points)
            if n_points == 3:
                score += 30
                feedback_parts.append("Topology correct (3 vertices).")
                
                # Check middle vertex
                p_mid = points[1] # (lon, lat)
                dist = math.sqrt((p_mid[0] - AMMAN_LON)**2 + (p_mid[1] - AMMAN_LAT)**2)
                
                if dist <= TOLERANCE:
                    score += 50
                    feedback_parts.append(f"Vertex location correct (dist: {dist:.3f}°).")
                    passed = True
                else:
                    feedback_parts.append(f"Vertex location too far (dist: {dist:.3f}°, expected < {TOLERANCE}°).")
            elif n_points > 3:
                score += 15
                feedback_parts.append(f"Too many vertices ({n_points}), but geometry modified.")
            else:
                feedback_parts.append(f"Geometry not modified (vertices: {n_points}).")

        conn.close()

    except Exception as e:
        feedback_parts.append(f"Verification error: {str(e)}")
    finally:
        if os.path.exists(temp_gpkg.name):
            os.unlink(temp_gpkg.name)
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }