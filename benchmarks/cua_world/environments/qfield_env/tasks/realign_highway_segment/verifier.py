#!/usr/bin/env python3
import json
import struct
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_gpkg_linestring(blob_hex):
    """
    Parses a GeoPackage Binary Geometry Blob for a LineString.
    Returns a list of (x, y) tuples.
    """
    try:
        if not blob_hex:
            return []
            
        # Convert hex string to bytes
        # blob_hex comes from sqlite X'...' format, might be just the hex string
        blob = bytes.fromhex(blob_hex)
        
        # GeoPackage Header parsing
        # Byte 0-1: Magic 0x4750
        # Byte 2-3: Magic 0x4B47
        if blob[0:4] != b'GPKG':
            logger.error("Invalid GeoPackage Geometry Magic")
            return []
            
        # Byte 4: Version (0)
        # Byte 5: Flags
        flags = blob[5]
        # Bit 0: Binary type (0=Standard, 1=Extended)
        # Bit 1-3: Empty
        # Bit 4: Empty geometry?
        # Bit 5: Envelope type (0=None, 1=32 bytes, 2=48, 3=64, 4=48, 5=64, 6=80)
        # Bit 6: Big Endian? (0=Little, 1=Big)
        
        envelope_indicator = (flags >> 1) & 0x07
        is_big_endian = (flags & 0x01) == 0 # Wait, standard says bit 0 is 0 for little endian? 
        # Actually GPKG spec: bit 0: 0=Little Endian, 1=Big Endian.
        is_big_endian = (flags & 0x01) == 1
        
        endian_char = '>' if is_big_endian else '<'
        
        # Byte 6-9: SRS_ID
        
        header_len = 8 # Magic(4) + Ver(1) + Flags(1) + SRS(4) = 10? No.
        # Header is usually fixed part then envelope.
        # Bytes 0-3: Magic
        # Byte 4: Ver
        # Byte 5: Flags
        # Bytes 6-9: SRS_ID
        offset = 10
        
        # Skip Envelope
        envelope_sizes = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64} # Simplified map
        if envelope_indicator in envelope_sizes:
            offset += envelope_sizes[envelope_indicator]
        else:
            # Fallback for standard 2D envelope (1)
            offset += 32
            
        # WKB Start
        # Byte Order (1 byte)
        wkb_byte_order = blob[offset]
        offset += 1
        wkb_endian = '>' if wkb_byte_order == 0 else '<'
        
        # Geometry Type (4 bytes)
        geom_type = struct.unpack(f'{wkb_endian}I', blob[offset:offset+4])[0]
        offset += 4
        
        # Check if LineString (2)
        # Note: GPKG WKB might use 2002 for LineStringM etc. We assume 2D LineString (2).
        if geom_type % 1000 != 2:
            logger.error(f"Geometry type is not LineString (Got {geom_type})")
            return []
            
        # Num Points (4 bytes)
        num_points = struct.unpack(f'{wkb_endian}I', blob[offset:offset+4])[0]
        offset += 4
        
        points = []
        for _ in range(num_points):
            x, y = struct.unpack(f'{wkb_endian}dd', blob[offset:offset+16])
            points.append((x, y))
            offset += 16
            
        return points
        
    except Exception as e:
        logger.error(f"Error parsing blob: {e}")
        return []

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance in km between two points."""
    R = 6371  # Earth radius in km
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def verify_realign_highway_segment(traj, env_info, task_info):
    """
    Verification for realign_highway_segment.
    Checks:
    1. Feature geometry has > 2 vertices (indicates modification).
    2. One vertex is close to Niamey.
    3. Start/End points remain anchored at Lagos/Algiers.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    niamey = metadata.get('target_vertex', {"lon": 2.11, "lat": 13.51})
    start_pt = metadata.get('endpoints', {}).get('start', {"lon": 3.3792, "lat": 6.5244})
    end_pt = metadata.get('endpoints', {}).get('end', {"lon": 3.0420, "lat": 36.7528})
    
    score = 0
    feedback = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Modification
    if result.get('file_modified', False):
        score += 10
        feedback.append("GeoPackage modified.")
    else:
        feedback.append("GeoPackage NOT modified.")
        return {"passed": False, "score": 0, "feedback": "Task failed: No changes detected in project file."}

    # 3. Parse Geometry
    geom_hex = result.get('geom_hex', '')
    points = parse_gpkg_linestring(geom_hex)
    
    if not points:
        return {"passed": False, "score": score, "feedback": "Could not read feature geometry. Feature might be deleted or corrupt."}

    # 4. Check Vertex Count
    # Original was 2 points. New should be at least 3.
    if len(points) >= 3:
        score += 30
        feedback.append(f"Vertex count increased to {len(points)} (Success).")
    elif len(points) == 2:
        feedback.append("Vertex count is still 2 (Failed to add vertex).")
    else:
        feedback.append(f"Invalid vertex count: {len(points)}.")

    # 5. Check Proximity to Niamey (Target)
    # We check if ANY vertex is within tolerance of Niamey
    target_hit = False
    min_dist = float('inf')
    tolerance_km = 150.0 # ~1.3 degrees, generous tolerance for finger tapping
    
    for px, py in points:
        dist = haversine_distance(py, px, niamey['lat'], niamey['lon'])
        if dist < min_dist:
            min_dist = dist
        if dist < tolerance_km:
            target_hit = True
            
    if target_hit:
        score += 40
        feedback.append(f"Route passes through Niamey (Closest vertex: {min_dist:.1f}km away).")
    else:
        feedback.append(f"Route misses Niamey. Closest vertex is {min_dist:.1f}km away.")

    # 6. Check Anchors (Start/End)
    # Ensure the user didn't just move the whole line
    # Note: Points in WKB might be reversed, so check both ends against both targets
    p_start = points[0]
    p_end = points[-1]
    
    # Check regular orientation
    dist_s_s = haversine_distance(p_start[1], p_start[0], start_pt['lat'], start_pt['lon'])
    dist_e_e = haversine_distance(p_end[1], p_end[0], end_pt['lat'], end_pt['lon'])
    
    # Check reverse orientation
    dist_s_e = haversine_distance(p_start[1], p_start[0], end_pt['lat'], end_pt['lon'])
    dist_e_s = haversine_distance(p_end[1], p_end[0], start_pt['lat'], start_pt['lon'])
    
    anchor_tolerance = 200.0 # km
    anchors_ok = False
    
    if (dist_s_s < anchor_tolerance and dist_e_e < anchor_tolerance):
        anchors_ok = True
    elif (dist_s_e < anchor_tolerance and dist_e_s < anchor_tolerance):
        anchors_ok = True
        
    if anchors_ok:
        score += 20
        feedback.append("Route endpoints preserved.")
    else:
        feedback.append("Route endpoints moved too far from original locations.")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }