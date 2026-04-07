#!/usr/bin/env python3
"""
Verifier for digitize_star_network task.
Analyzes the GeoPackage to verify a star topology of fiber routes.
"""

import json
import os
import sqlite3
import struct
import math
import tempfile
import logging
from typing import List, Tuple, Dict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Geometry Utilities ---

def parse_gpkg_header(blob: bytes) -> Tuple[int, bytes]:
    """
    Parses GeoPackage Binary Header.
    Returns (srs_id, wkb_bytes).
    """
    # Magic (2) + Version (1) + Flags (1)
    # Flags: bit 0: empty geometry, bit 5: extended type
    flags = blob[3]
    
    # Envelope size determination
    envelope_indicator = (flags >> 1) & 0x07
    envelope_sizes = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}
    envelope_len = envelope_sizes.get(envelope_indicator, 0)
    
    # SRS ID is bytes 4-7 (int32, usually little endian)
    srs_id = struct.unpack('<i', blob[4:8])[0]
    
    # Header length = 8 + envelope_len
    header_len = 8 + envelope_len
    
    return srs_id, blob[header_len:]

def parse_wkb_linestring(wkb: bytes) -> List[Tuple[float, float]]:
    """
    Parses a WKB LineString to a list of (x, y) coordinates.
    Assumes 2D coordinates for simplicity.
    """
    byte_order = wkb[0]
    endian = '<' if byte_order == 1 else '>'
    
    # WKB Type (uint32)
    geom_type = struct.unpack(endian + 'I', wkb[1:5])[0]
    
    # Check if LineString (2) or LineStringZ (1002) or similar
    # We only care about X,Y
    
    num_points = struct.unpack(endian + 'I', wkb[5:9])[0]
    points = []
    offset = 9
    
    # Point size: 16 bytes for 2D (double x, double y)
    # If Z/M present, we skip them. Standard LineString is 2D.
    # For robustness, we assume standard 2D WKB LineString here (Type 2)
    point_size = 16 
    
    for _ in range(num_points):
        if offset + 16 > len(wkb):
            break
        x, y = struct.unpack(endian + 'dd', wkb[offset:offset+16])
        points.append((x, y))
        offset += point_size
        
    return points

def haversine_km(lat1, lon1, lat2, lon2):
    """Calculate Haversine distance in km."""
    R = 6371  # Earth radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

# --- Verification Logic ---

def verify_digitize_star_network(traj, env_info, task_info):
    """
    Verifies that the agent created 3 lines connecting Vienna to targets.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata targets
    metadata = task_info.get('metadata', {})
    center = metadata.get('targets', {}).get('center', {"lat": 48.2082, "lon": 16.3738})
    spokes = metadata.get('targets', {}).get('spokes', [])
    tolerance_km = metadata.get('tolerance_km', 25.0)

    # Temporary files
    temp_gpkg = tempfile.NamedTemporaryFile(delete=False, suffix='.gpkg').name
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name

    try:
        # Copy files from environment
        # Note: export_result.sh puts gpkg at /sdcard/task_result.gpkg
        copy_from_env("/sdcard/task_result.gpkg", temp_gpkg)
        copy_from_env("/sdcard/task_result.json", temp_json)

        # Basic Check: File exists and modified
        with open(temp_json, 'r') as f:
            result_meta = json.load(f)
        
        if not result_meta.get('file_modified', False):
            return {"passed": False, "score": 0, "feedback": "Project file was not modified (do nothing detected)."}

        # Analyze Database
        conn = sqlite3.connect(temp_gpkg)
        cursor = conn.cursor()
        
        # Check if table exists and get rows
        try:
            cursor.execute("SELECT geom, link_id, status FROM network_lines")
            rows = cursor.fetchall()
        except sqlite3.OperationalError:
            return {"passed": False, "score": 0, "feedback": "Table 'network_lines' not found or empty."}
        
        if not rows:
            return {"passed": False, "score": 0, "feedback": "No features found in 'network_lines' layer."}

        # Analyze Features
        valid_hub_starts = 0
        valid_links = {spoke['id']: False for spoke in spokes}
        correct_attributes = 0
        total_features = len(rows)
        
        feedback_details = []

        for blob, link_id, status in rows:
            if not blob:
                continue
            
            # Parse geometry
            try:
                srs, wkb = parse_gpkg_header(blob)
                points = parse_wkb_linestring(wkb)
            except Exception as e:
                feedback_details.append(f"Error parsing geometry: {str(e)}")
                continue

            if len(points) < 2:
                feedback_details.append("Feature has fewer than 2 points")
                continue

            # Start and End points (lon, lat)
            start_lon, start_lat = points[0]
            end_lon, end_lat = points[-1]

            # Check Hub (Vienna) proximity
            # We allow start OR end to be the hub (agent might draw backwards)
            dist_start_hub = haversine_km(start_lat, start_lon, center['lat'], center['lon'])
            dist_end_hub = haversine_km(end_lat, end_lon, center['lat'], center['lon'])
            
            is_start_hub = dist_start_hub < tolerance_km
            is_end_hub = dist_end_hub < tolerance_km

            if is_start_hub:
                valid_hub_starts += 1
                remote_lat, remote_lon = end_lat, end_lon
            elif is_end_hub:
                valid_hub_starts += 1
                remote_lat, remote_lon = start_lat, start_lon
            else:
                feedback_details.append(f"Feature does not connect to Vienna (Closest end: {min(dist_start_hub, dist_end_hub):.1f}km)")
                continue

            # Check Spoke connection
            matched_spoke = None
            for spoke in spokes:
                dist = haversine_km(remote_lat, remote_lon, spoke['lat'], spoke['lon'])
                if dist < tolerance_km:
                    matched_spoke = spoke
                    break
            
            if matched_spoke:
                # Check attributes
                attr_ok = True
                if link_id != matched_spoke['id']:
                    attr_ok = False
                    feedback_details.append(f"Wrong Link ID for {matched_spoke['name']}: found '{link_id}', expected '{matched_spoke['id']}'")
                
                if status != 'planned':
                    attr_ok = False
                    feedback_details.append(f"Wrong status: found '{status}', expected 'planned'")

                if attr_ok:
                    valid_links[matched_spoke['id']] = True
                    correct_attributes += 1
            else:
                feedback_details.append(f"Feature connects Vienna to unknown location ({remote_lat:.4f}, {remote_lon:.4f})")

        conn.close()

        # Scoring
        score = 0
        
        # 1. Hub Connection (Max 20)
        # 3 features connecting to hub = full points
        hub_score = min(20, valid_hub_starts * 7)
        score += hub_score

        # 2. Spoke Connections (Max 60, 20 per correct link)
        spoke_score = 0
        for spoke_id, valid in valid_links.items():
            if valid:
                spoke_score += 20
        score += spoke_score

        # 3. Attributes (Max 20)
        # Already checked implicitly in valid_links, but we give bonus for perfect attr matches across board if count matches
        if correct_attributes >= 3:
            score += 20
        elif correct_attributes > 0:
            score += 10

        passed = score >= 80

        feedback = f"Score: {score}/100. "
        if passed:
            feedback += "Great job! Star network digitized correctly."
        else:
            feedback += "Issues found: " + "; ".join(feedback_details)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification failed with exception: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_gpkg):
            os.unlink(temp_gpkg)
        if os.path.exists(temp_json):
            os.unlink(temp_json)