#!/usr/bin/env python3
"""
Verifier for multi_site_survey task.

Checks for 3 specific observation points in the QField GeoPackage.
"""

import json
import os
import sqlite3
import struct
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_gpkg_point(blob):
    """
    Parse a GeoPackage Binary Geometry Blob to extract Point coordinates.
    Format: Header (flags, srs_id) + WKB
    """
    try:
        if not blob or len(blob) < 8:
            return None
            
        # Header parsing
        # magic = blob[0:2] # 0x4750
        # version = blob[2]
        flags = blob[3]
        
        # Determine envelope size based on flags
        # Bits 3-1 (0-indexed) determine envelope type
        envelope_indicator = (flags >> 1) & 0x07
        envelope_sizes = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}
        envelope_len = envelope_sizes.get(envelope_indicator, 0)
        
        header_len = 8 + envelope_len
        wkb_start = header_len
        
        if len(blob) < wkb_start + 5:
            return None
            
        # WKB parsing (Assume Little Endian for simplicity, usually 0x01)
        byte_order = blob[wkb_start]
        endian = '<' if byte_order == 1 else '>'
        
        # Geometry Type (4 bytes)
        geom_type = struct.unpack(endian + 'I', blob[wkb_start+1:wkb_start+5])[0]
        
        # Check if Point (Type 1 or 1001/2001/3001)
        # 2D Point = 1
        if geom_type != 1 and (geom_type % 1000) != 1:
            return None
            
        # Read X, Y (doubles, 8 bytes each)
        x = struct.unpack(endian + 'd', blob[wkb_start+5:wkb_start+13])[0]
        y = struct.unpack(endian + 'd', blob[wkb_start+13:wkb_start+21])[0]
        
        return (x, y)
    except Exception as e:
        logger.warning(f"Failed to parse geometry: {e}")
        return None

def haversine_distance_deg(lat1, lon1, lat2, lon2):
    """Calculate euclidean distance in degrees (sufficient for verification)."""
    return math.sqrt((lat2 - lat1)**2 + (lon2 - lon1)**2)

def verify_multi_site_survey(traj, env_info, task_info):
    """
    Verify 3 observation points were created at correct locations.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_sites = metadata.get('target_sites', [])
    gpkg_path_in_env = metadata.get('gpkg_path')
    
    # Temp files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_gpkg = tempfile.NamedTemporaryFile(delete=False, suffix='.gpkg').name
    
    score = 0
    feedback_lines = []
    
    try:
        # 1. Get Result JSON
        try:
            copy_from_env("/sdcard/task_result.json", temp_json)
            with open(temp_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # 2. Get GeoPackage
        try:
            copy_from_env(gpkg_path_in_env, temp_gpkg)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve GeoPackage: {e}"}

        # 3. Analyze GeoPackage
        conn = sqlite3.connect(temp_gpkg)
        cursor = conn.cursor()
        
        # Get table info/columns
        cursor.execute("PRAGMA table_info(observations)")
        columns = {row[1]: row[0] for row in cursor.fetchall()} # name -> index mapping won't work for dict factory, just get names
        
        # Assume standard schema from prompt description
        # Query new features. We assume 'fid' or 'id' is autoincrement.
        # Ideally, we count records.
        
        # Find all records
        cursor.execute("SELECT * FROM observations")
        rows = cursor.fetchall()
        
        # Get column names from description if not standard, but let's try to map by name
        col_names = [description[0] for description in cursor.description]
        
        # Helper to get value
        def get_val(row, col):
            if col in col_names:
                return row[col_names.index(col)]
            return None
            
        # Parse all points
        parsed_points = []
        for row in rows:
            geom_blob = get_val(row, "geom") # QField/GPKG usually uses 'geom' or 'geometry'
            if not geom_blob:
                geom_blob = get_val(row, "geometry")
            
            coords = parse_gpkg_point(geom_blob)
            
            parsed_points.append({
                "id": get_val(row, "fid"),
                "observer": get_val(row, "observer"),
                "type": get_val(row, "observation_type"),
                "notes": get_val(row, "notes"),
                "coords": coords
            })
            
        conn.close()
        
        # Evaluate Findings
        # We expect 3 NEW points.
        # Since we don't know the exact starting count in the verifier (setup script ran in env),
        # we look for points that match our target criteria.
        # The prompt implies starting state has 8 observations (from setup_qfield.sh in prompt context).
        # So we look for points with our specific attributes.
        
        matches = {site['name']: False for site in target_sites}
        new_records_count = 0
        
        for p in parsed_points:
            # Filter by Observer to narrow down to agent's work
            if str(p.get("observer")) != "Rivera":
                continue
                
            new_records_count += 1
            
            p_lat = p['coords'][1] if p['coords'] else 0
            p_lon = p['coords'][0] if p['coords'] else 0
            p_notes = str(p.get('notes', ''))
            p_type = str(p.get('type', ''))
            
            # Check against targets
            for site in target_sites:
                if matches[site['name']]: continue # Already found this site
                
                # Check proximity
                dist = haversine_distance_deg(p_lat, p_lon, site['lat'], site['lon'])
                
                # Check attributes
                notes_match = site['notes_keyword'].lower() in p_notes.lower()
                type_match = "habitat" in p_type.lower()
                
                if dist < 2.0 and notes_match and type_match:
                    matches[site['name']] = True
                    feedback_lines.append(f"✓ Found valid entry for {site['name']}")
                    score += 25 # Per site score
                    break
        
        # Scoring Logic
        # 15 points for creating 3 records (we found at least 3 matching 'Rivera'?)
        if new_records_count >= 3:
            score += 15
            feedback_lines.append(f"✓ Created {new_records_count} new records")
        elif new_records_count > 0:
            score += (new_records_count * 5)
            feedback_lines.append(f"⚠ Created {new_records_count} records (expected 3)")
        else:
            feedback_lines.append("✗ No records found with observer 'Rivera'")
            
        # Anti-gaming (Time check)
        task_start = result_data.get('task_start', 0)
        # Note: We can't easily check row creation time in GPKG unless there's a timestamp column
        # and we trust the agent set it.
        # We assume if the record has the specific content requested, it was made by the agent.
        score += 10 # Baseline for attempting task
        
        passed = (score >= 65)
        
    except Exception as e:
        logger.error(f"Verification Error: {e}")
        return {"passed": False, "score": score, "feedback": f"Error during verification: {str(e)}"}
    finally:
        if os.path.exists(temp_json): os.remove(temp_json)
        if os.path.exists(temp_gpkg): os.remove(temp_gpkg)
        
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "\n".join(feedback_lines)
    }