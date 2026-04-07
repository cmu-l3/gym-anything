#!/usr/bin/env python3
"""
Verifier for expand_sanctuary_boundary task.

Checks if the agent modified the 'Sanctuary A' polygon in the GeoPackage
to geometrically contain the 'Water Source' point.
"""

import json
import os
import struct
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- GEOMETRY UTILS (No external dependencies like shapely) ---

def parse_gpkg_blob(blob):
    """
    Parses a GeoPackage Geometry Binary Blob.
    Returns standard WKB bytes (skipping header).
    """
    if not blob or len(blob) < 8:
        return None
        
    # Magic 0x4750 (GP)
    magic = blob[0:2]
    if magic != b'GP':
        return None
        
    # Version (byte 2) - usually 0
    # Flags (byte 3)
    flags = blob[3]
    
    # Binary Envelope Indicator (bits 1-3 of flags)
    envelope_indicator = (flags >> 1) & 0x07
    
    header_len = 8 # Magic(2) + Ver(1) + Flags(1) + SRS_ID(4)
    
    if envelope_indicator == 1:
        header_len += 32 # 4 doubles
    elif envelope_indicator == 2:
        header_len += 48 # 6 doubles
    elif envelope_indicator == 3:
        header_len += 48 # 6 doubles
    elif envelope_indicator == 4:
        header_len += 64 # 8 doubles
        
    return blob[header_len:]

def parse_wkb_point(wkb):
    """Parses WKB Point. Returns (x, y)."""
    # Byte order: 0=Big Endian, 1=Little Endian
    byte_order = wkb[0]
    endian = '<' if byte_order == 1 else '>'
    
    # Type (4 bytes)
    geom_type = struct.unpack(endian + 'I', wkb[1:5])[0]
    
    # Check if point (1)
    if geom_type != 1:
        return None
        
    x, y = struct.unpack(endian + 'dd', wkb[5:21])
    return (x, y)

def parse_wkb_polygon(wkb):
    """Parses WKB Polygon. Returns list of rings, where ring is list of (x,y)."""
    byte_order = wkb[0]
    endian = '<' if byte_order == 1 else '>'
    
    geom_type = struct.unpack(endian + 'I', wkb[1:5])[0]
    
    # Check if polygon (3)
    if geom_type != 3:
        return None
        
    num_rings = struct.unpack(endian + 'I', wkb[5:9])[0]
    offset = 9
    rings = []
    
    for _ in range(num_rings):
        num_points = struct.unpack(endian + 'I', wkb[offset:offset+4])[0]
        offset += 4
        ring = []
        for _ in range(num_points):
            x, y = struct.unpack(endian + 'dd', wkb[offset:offset+16])
            ring.append((x, y))
            offset += 16
        rings.append(ring)
        
    return rings

def point_in_polygon(point, polygon_rings):
    """
    Ray casting algorithm to check if point is inside polygon.
    Polygon is defined by list of rings (first is exterior, others interior holes).
    """
    x, y = point
    exterior = polygon_rings[0]
    
    # Check exterior ring
    inside = False
    n = len(exterior)
    p1x, p1y = exterior[0]
    for i in range(n + 1):
        p2x, p2y = exterior[i % n]
        if y > min(p1y, p2y):
            if y <= max(p1y, p2y):
                if x <= max(p1x, p2x):
                    if p1y != p2y:
                        xinters = (y - p1y) * (p2x - p1x) / (p2y - p1y) + p1x
                    if p1x == p2x or x <= xinters:
                        inside = not inside
        p1x, p1y = p2x, p2y
        
    if not inside:
        return False
        
    # Check holes (if any)
    # If inside any hole, then it's outside the polygon
    for hole in polygon_rings[1:]:
        in_hole = False
        n = len(hole)
        p1x, p1y = hole[0]
        for i in range(n + 1):
            p2x, p2y = hole[i % n]
            if y > min(p1y, p2y):
                if y <= max(p1y, p2y):
                    if x <= max(p1x, p2x):
                        if p1y != p2y:
                            xinters = (y - p1y) * (p2x - p1x) / (p2y - p1y) + p1x
                        if p1x == p2x or x <= xinters:
                            in_hole = not in_hole
            p1x, p1y = p2x, p2y
        if in_hole:
            return False
            
    return True

# --- VERIFIER ---

def verify_expand_sanctuary_boundary(traj, env_info, task_info):
    """
    Verifies that the agent edited the polygon to include the point.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # 1. Retrieve Result JSON and GeoPackage
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gpkg = tempfile.NamedTemporaryFile(delete=False, suffix='.gpkg')
    
    try:
        # Get result JSON
        try:
            copy_from_env("/sdcard/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
            
        # Check if file was modified
        if not result.get("gpkg_modified", False):
            feedback_parts.append("GeoPackage was not modified (do nothing detected)")
        else:
            score += 10
            feedback_parts.append("GeoPackage modified")
            
        # Get GeoPackage
        try:
            copy_from_env(result.get("gpkg_path", ""), temp_gpkg.name)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve GeoPackage: {e}"}

        # 2. Analyze Geometry
        import sqlite3
        conn = sqlite3.connect(temp_gpkg.name)
        cursor = conn.cursor()
        
        # Get Polygon
        cursor.execute("SELECT geom FROM sanctuary_zones WHERE name LIKE '%Sanctuary A%'")
        poly_row = cursor.fetchone()
        
        # Get Point
        cursor.execute("SELECT geom FROM critical_water_sources WHERE name LIKE '%Water Source%'")
        point_row = cursor.fetchone()
        
        conn.close()
        
        if not poly_row or not point_row:
            return {"passed": False, "score": score, "feedback": "Required features missing from database"}
            
        # Parse Geometries
        poly_wkb = parse_gpkg_blob(poly_row[0])
        point_wkb = parse_gpkg_blob(point_row[0])
        
        if not poly_wkb or not point_wkb:
             return {"passed": False, "score": score, "feedback": "Failed to parse geometry blobs"}
             
        poly_rings = parse_wkb_polygon(poly_wkb)
        point_coords = parse_wkb_point(point_wkb)
        
        if not poly_rings or not point_coords:
            return {"passed": False, "score": score, "feedback": "Invalid geometry data structure"}
            
        # 3. Check Containment (Primary Goal)
        is_contained = point_in_polygon(point_coords, poly_rings)
        
        if is_contained:
            score += 50
            feedback_parts.append("Success: Water Source is inside Sanctuary A")
        else:
            feedback_parts.append("Fail: Water Source is still OUTSIDE Sanctuary A")
            
        # 4. Check Area Increase (Sanity Check)
        # Simple area calculation for polygon exterior ring
        def polygon_area(ring):
            area = 0.0
            n = len(ring)
            for i in range(n):
                j = (i + 1) % n
                area += ring[i][0] * ring[j][1]
                area -= ring[j][0] * ring[i][1]
            return abs(area) / 2.0
            
        final_area = polygon_area(poly_rings[0])
        initial_area_approx = task_info.get("metadata", {}).get("initial_area_approx", 0.0002)
        
        if final_area > initial_area_approx * 1.05: # At least 5% bigger
            score += 20
            feedback_parts.append("Polygon area increased appropriately")
        elif final_area < initial_area_approx * 0.95:
            feedback_parts.append("Polygon area decreased (unexpected)")
        else:
            feedback_parts.append("Polygon area barely changed")

        # 5. VLM / Screenshot verification would go here (Stub for now, assume external VLM evaluator checks trajectory)
        # We give partial points if file modified but geometry fail, assuming effort
        if score < 60 and result.get("gpkg_modified"):
             score += 10 # Effort points

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification error: {e}"}
        
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_gpkg.name): os.unlink(temp_gpkg.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }