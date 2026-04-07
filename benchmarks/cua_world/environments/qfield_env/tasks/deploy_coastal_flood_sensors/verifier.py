#!/usr/bin/env python3
import json
import os
import sqlite3
import struct
import tempfile
import math

def parse_gpkg_point(blob):
    """
    Parses a GeoPackage Binary Geometry blob to extract Point coordinates.
    See: http://www.geopackage.org/spec/#gpb_format
    
    Structure:
    - Header: 
      - Magic (2 bytes): 0x4750 ('GP')
      - Version (1 byte): 0
      - Flags (1 byte): 
         - Bit 0: 0=BigEndian, 1=LittleEndian
         - Bit 1-3: Envelope type (0=None)
      - SRS_ID (4 bytes)
    - Envelope (Optional, var size)
    - WKBGeometry (Well-Known Binary)
    """
    if not blob or len(blob) < 8:
        return None

    # Parse Header
    magic = blob[0:2]
    if magic != b'GP':
        return None
    
    flags = blob[3]
    # Bit 0: Endianness (1 = Little Endian)
    is_little_endian = (flags & 1) == 1
    # Bits 1-3: Envelope (0 = None, 1-4 = varied sizes)
    envelope_indicator = (flags >> 1) & 0x07
    
    # Calculate header length
    # Fixed header is 8 bytes
    offset = 8
    
    # Add Envelope length
    if envelope_indicator == 1:
        offset += 32
    elif envelope_indicator == 2:
        offset += 48
    elif envelope_indicator == 3:
        offset += 48
    elif envelope_indicator == 4:
        offset += 64
        
    if len(blob) < offset + 21: # Header + WKB Point (1 + 4 + 8 + 8)
        return None

    # WKB Part
    # Byte order byte (1 byte)
    wkb_byte_order = blob[offset]
    wkb_little_endian = (wkb_byte_order == 1)
    
    # Geometry Type (4 bytes) - We expect 1 (Point) or 1001 (Point Z) etc.
    # For this task, standard 2D point is expected (type 1)
    
    # Coordinates start at offset + 1 (order) + 4 (type) = offset + 5
    coord_offset = offset + 5
    
    endian_char = '<' if wkb_little_endian else '>'
    
    try:
        x = struct.unpack(f'{endian_char}d', blob[coord_offset:coord_offset+8])[0]
        y = struct.unpack(f'{endian_char}d', blob[coord_offset+8:coord_offset+16])[0]
        return (x, y)
    except Exception as e:
        print(f"Error parsing WKB: {e}")
        return None

def verify_deploy_sensors(traj, env_info, task_info):
    """
    Verifies that the agent created two sensor points with correct offsets relative to capitals.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup
    score = 0
    feedback = []
    temp_dir = tempfile.mkdtemp()
    local_gpkg = os.path.join(temp_dir, "task_output.gpkg")
    local_json = os.path.join(temp_dir, "task_result.json")
    
    try:
        # 1. Retrieve Artifacts
        try:
            copy_from_env("/sdcard/task_output.gpkg", local_gpkg)
            copy_from_env("/sdcard/task_result.json", local_json)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {e}"}

        # 2. Open Database
        conn = sqlite3.connect(local_gpkg)
        cursor = conn.cursor()

        # 3. Get Reference Coordinates (Ground Truth from the file itself)
        # We query the capitals table to get the exact location of Jakarta and Manila
        # This handles any minor coordinate variants in the dataset
        capitals = {}
        try:
            cursor.execute("SELECT name, geom FROM world_capitals WHERE name IN ('Jakarta', 'Manila')")
            for row in cursor.fetchall():
                name = row[0]
                geom = row[1]
                coords = parse_gpkg_point(geom)
                if coords:
                    capitals[name] = coords
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error querying capitals: {e}"}

        if 'Jakarta' not in capitals or 'Manila' not in capitals:
             return {"passed": False, "score": 0, "feedback": "Could not find Jakarta or Manila in dataset to establish ground truth."}

        jakarta_gt = capitals['Jakarta'] # (lon, lat)
        manila_gt = capitals['Manila']   # (lon, lat)

        # 4. Get User Created Sensors
        sensors = {}
        try:
            # Query for features created/modified? 
            # We look for features with specific names as requested in task
            cursor.execute("SELECT name, geom FROM field_observations WHERE name LIKE 'Sensor_%'")
            for row in cursor.fetchall():
                name = row[0]
                geom = row[1]
                coords = parse_gpkg_point(geom)
                if coords:
                    sensors[name] = coords
        except Exception as e:
            feedback.append(f"Error querying observations: {e}")

        conn.close()

        # 5. Evaluate Jakarta Sensor (North)
        # Expected: Lat + 0.1, Lon same
        j_sensor = sensors.get('Sensor_JKT_North')
        if j_sensor:
            score += 20 # Existence
            
            d_lat = j_sensor[1] - jakarta_gt[1]
            d_lon = j_sensor[0] - jakarta_gt[0]
            
            # Check Direction (North)
            if d_lat > 0:
                score += 5
                
            # Check Precision (0.1 deg N)
            # Tolerance: +/- 0.05
            if 0.05 <= d_lat <= 0.15 and abs(d_lon) < 0.05:
                score += 25
                feedback.append("Jakarta sensor placement: Excellent.")
            elif d_lat > 0:
                score += 10 # Wrong distance but right direction
                feedback.append(f"Jakarta sensor direction correct, but offset {d_lat:.4f} is not 0.1.")
            else:
                feedback.append("Jakarta sensor is not North of city.")
        else:
            feedback.append("Missing feature: 'Sensor_JKT_North'.")

        # 6. Evaluate Manila Sensor (West)
        # Expected: Lon - 0.1, Lat same
        m_sensor = sensors.get('Sensor_MNL_West')
        if m_sensor:
            score += 20 # Existence
            
            d_lat = m_sensor[1] - manila_gt[1]
            d_lon = m_sensor[0] - manila_gt[0]
            
            # Check Direction (West)
            if d_lon < 0:
                score += 5
            
            # Check Precision (0.1 deg W)
            if -0.15 <= d_lon <= -0.05 and abs(d_lat) < 0.05:
                score += 25
                feedback.append("Manila sensor placement: Excellent.")
            elif d_lon < 0:
                score += 10
                feedback.append(f"Manila sensor direction correct, but offset {d_lon:.4f} is not -0.1.")
            else:
                feedback.append("Manila sensor is not West of city.")
        else:
            feedback.append("Missing feature: 'Sensor_MNL_West'.")
            
        passed = score >= 70
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)