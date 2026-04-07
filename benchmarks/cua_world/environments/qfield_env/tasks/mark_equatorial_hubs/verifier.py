#!/usr/bin/env python3
"""
Verifier for mark_equatorial_hubs task.

Verifies that the agent has added 3 specific points to the GeoPackage
at the correct coordinates with the correct attributes.
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

def verify_mark_equatorial_hubs(traj, env_info, task_info):
    """
    Verify the 3 equatorial hubs were created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', [])
    tolerance = metadata.get('tolerance_degrees', 1.5)

    # Temporary files for extraction
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gpkg = tempfile.NamedTemporaryFile(delete=False, suffix='.gpkg')

    try:
        # 1. Get Result JSON
        try:
            copy_from_env("/data/local/tmp/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result JSON: {str(e)}"}

        gpkg_path = result_data.get('gpkg_path')
        if not gpkg_path:
            return {"passed": False, "score": 0, "feedback": "GeoPackage path not found in result"}

        # 2. Get GeoPackage File
        try:
            copy_from_env(gpkg_path, temp_gpkg.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve GeoPackage file: {str(e)}"}

        # 3. Analyze Database
        conn = sqlite3.connect(temp_gpkg.name)
        cursor = conn.cursor()

        # Get all features from field_observations
        # We assume standard GeoPackage structure. 
        # Geometry is usually a blob. We need to parse the GPKG binary header.
        try:
            cursor.execute("SELECT name, notes, geom FROM field_observations")
            rows = cursor.fetchall()
        except sqlite3.Error as e:
            return {"passed": False, "score": 0, "feedback": f"Database query error: {str(e)}"}
        finally:
            conn.close()

        # 4. Verify Targets
        score = 0
        feedback = []
        
        # Anti-gaming: Check if file was actually modified
        task_start = result_data.get('task_start', 0)
        gpkg_mtime = result_data.get('gpkg_mtime', 0)
        
        if gpkg_mtime <= task_start:
             return {"passed": False, "score": 0, "feedback": "GeoPackage was not modified during the task."}

        # Analyze found features
        # We need to parse geometries to get Lat/Lon
        found_features = []
        for name, notes, geom_blob in rows:
            lat, lon = parse_gpkg_point(geom_blob)
            if lat is not None and lon is not None:
                found_features.append({
                    "name": name,
                    "notes": notes,
                    "lat": lat,
                    "lon": lon
                })

        # Check each target
        targets_met = 0
        
        for target in targets:
            t_city = target['city']
            t_lat = target['lat']
            t_lon = target['lon']
            t_name = target['expected_name']
            t_notes = target['expected_notes']
            
            # Find best match for this target
            best_match = None
            min_dist = float('inf')
            
            for feat in found_features:
                # Euclidean distance in degrees is fine for this scale/tolerance
                dist = math.sqrt((feat['lat'] - t_lat)**2 + (feat['lon'] - t_lon)**2)
                
                if dist < tolerance:
                    # Check if this feature is a candidate
                    # We prioritize spatial match
                    if dist < min_dist:
                        min_dist = dist
                        best_match = feat
            
            if best_match:
                feedback.append(f"✅ Location found for {t_city} (dist: {min_dist:.2f}°)")
                score += 20 # Points for location
                
                # Check attributes
                attr_score = 0
                actual_name = str(best_match['name']) if best_match['name'] else ""
                actual_notes = str(best_match['notes']) if best_match['notes'] else ""
                
                if t_name.lower() in actual_name.lower():
                    attr_score += 5
                    feedback.append(f"  - Name correct: {actual_name}")
                else:
                    feedback.append(f"  - Name mismatch: expected '{t_name}', got '{actual_name}'")
                    
                if t_notes.lower() in actual_notes.lower():
                    attr_score += 5
                    feedback.append(f"  - Notes correct: {actual_notes}")
                else:
                    feedback.append(f"  - Notes mismatch: expected '{t_notes}', got '{actual_notes}'")
                
                score += attr_score
                if attr_score == 10:
                    targets_met += 1
            else:
                feedback.append(f"❌ No feature found near {t_city} ({t_lat}, {t_lon})")

        # Anti-gaming: Check for duplicates or mess
        initial_count = result_data.get('initial_count', 0)
        final_count = result_data.get('final_count', len(rows))
        created_count = final_count - initial_count
        
        if created_count == 3:
            score += 10
            feedback.append("✅ Exactly 3 features created.")
        elif created_count > 3:
            score += 5
            feedback.append(f"⚠️ Created {created_count} features (expected 3).")
        else:
            feedback.append(f"⚠️ Created {created_count} features (expected 3).")

        passed = (targets_met >= 2) and (score >= 70)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback)
        }

    except Exception as e:
        import traceback
        return {"passed": False, "score": 0, "feedback": f"Verification failed with error: {str(e)}\n{traceback.format_exc()}"}
    finally:
        # Cleanup
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_gpkg.name):
            os.unlink(temp_gpkg.name)

def parse_gpkg_point(blob):
    """
    Parse a GeoPackage Binary Geometry blob to extract Point coordinates.
    Format spec: http://www.geopackage.org/spec/#gpb_format
    """
    if not blob or len(blob) < 8:
        return None, None
        
    # Header: Magic(2) + Version(1) + Flags(1) + SRS_ID(4)
    magic = blob[0:2]
    if magic != b'GP':
        return None, None # Not a GPKG geometry
        
    flags = blob[3]
    # Bit 0: Envelope check (0=no envelope, 1-4=envelope types)
    # Bit 5: Endianness (0=Big, 1=Little)
    
    little_endian = (flags & 0b00000001) == 1
    envelope_indicator = (flags >> 1) & 0b00000111
    
    # Envelope sizes
    envelope_sizes = {0:0, 1:32, 2:48, 3:48, 4:64}
    envelope_size = envelope_sizes.get(envelope_indicator, 0)
    
    offset = 8 + envelope_size
    
    if len(blob) < offset + 5: # WKB point needs at least byte order + type + coords
        return None, None
        
    # WKB part
    wkb_bytes = blob[offset:]
    
    # WKB Byte Order (1 byte)
    wkb_endian_byte = wkb_bytes[0]
    is_wkb_little = (wkb_endian_byte == 1)
    
    endian_char = '<' if is_wkb_little else '>'
    
    # WKB Type (4 bytes)
    wkb_type = struct.unpack(endian_char + 'I', wkb_bytes[1:5])[0]
    
    # Handle standard WKB Point (Type 1) or PointZ/M variants usually 1001/2001/3001
    # We assume 2D point for basic lat/lon extraction, or extract X/Y from Z points
    
    # Coordinates (2 doubles = 16 bytes)
    try:
        x, y = struct.unpack(endian_char + 'dd', wkb_bytes[5:21])
        return y, x # Lat, Lon
    except:
        return None, None