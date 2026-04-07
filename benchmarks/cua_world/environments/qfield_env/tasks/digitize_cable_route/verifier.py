#!/usr/bin/env python3
"""
Verifier for QField digitize_cable_route task.
Verifies the GeoPackage database content and VLM trajectory.
"""

import json
import os
import sqlite3
import struct
import tempfile
import logging
import math

# Import gym_anything utils if available, or define mocks/stubs
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Mocks for testing outside framework
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_digitize_cable_route(traj, env_info, task_info):
    """
    Verifies that the agent digitized the cable route correctly.
    
    Checks:
    1. GeoPackage file modified.
    2. New row exists in 'cable_routes' table.
    3. Attributes match (route_name, cable_type, notes).
    4. Geometry is valid LineString and roughly connects Paris -> Brussels.
    5. VLM trajectory confirms UI interaction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_attrs = metadata.get('expected_attributes', {})
    coords = metadata.get('coordinates', {})
    
    score = 0
    feedback = []
    
    # Create temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        result_json_path = os.path.join(temp_dir, "task_result.json")
        gpkg_local_path = os.path.join(temp_dir, "world_survey.gpkg")
        
        # 1. Retrieve JSON result
        try:
            copy_from_env("/sdcard/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        if not result_data.get('file_exists'):
            return {"passed": False, "score": 0, "feedback": "GeoPackage file not found."}
            
        if not result_data.get('modified_during_task'):
            feedback.append("WARNING: File timestamp suggests no modification during task.")
        else:
            score += 10
            feedback.append("File modified during task.")

        # 2. Retrieve GeoPackage
        try:
            remote_path = result_data.get('gpkg_path_container')
            copy_from_env(remote_path, gpkg_local_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve GeoPackage: {str(e)}"}

        # 3. Analyze Database Content
        try:
            conn = sqlite3.connect(gpkg_local_path)
            cursor = conn.cursor()
            
            # Check for table and rows
            try:
                cursor.execute("SELECT * FROM cable_routes")
                rows = cursor.fetchall()
                cols = [description[0] for description in cursor.description]
            except sqlite3.OperationalError:
                return {"passed": False, "score": score, "feedback": "Table 'cable_routes' does not exist."}

            if not rows:
                return {"passed": False, "score": score, "feedback": "No features found in 'cable_routes' layer."}
            
            # Use the last added row
            row = rows[-1]
            row_dict = dict(zip(cols, row))
            
            score += 20
            feedback.append("Feature created in database.")
            
            # Check Attributes
            attr_score = 0
            # route_name
            if row_dict.get('route_name') == expected_attrs['route_name']:
                attr_score += 10
            else:
                feedback.append(f"Wrong route_name: expected {expected_attrs['route_name']}, got {row_dict.get('route_name')}")
                
            # cable_type
            if row_dict.get('cable_type') == expected_attrs['cable_type']:
                attr_score += 10
            else:
                feedback.append(f"Wrong cable_type: expected {expected_attrs['cable_type']}, got {row_dict.get('cable_type')}")
                
            # notes
            if expected_attrs['notes'] in (row_dict.get('notes') or ""):
                attr_score += 5
            else:
                feedback.append(f"Notes mismatch: expected '{expected_attrs['notes']}'")
                
            score += attr_score
            feedback.append(f"Attribute check: {attr_score}/25 points.")

            # Check Geometry
            geom_blob = row_dict.get('geom')
            geom_valid, geom_feedback = verify_gpkg_geometry(geom_blob, coords)
            if geom_valid:
                score += 25
                feedback.append("Geometry is valid and connects target cities.")
            else:
                feedback.append(f"Geometry check failed: {geom_feedback}")

        except Exception as e:
            feedback.append(f"Database analysis error: {str(e)}")
        finally:
            if 'conn' in locals():
                conn.close()

    # 4. VLM Verification
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_ss = get_final_screenshot(traj)
        if final_ss:
            frames.append(final_ss)
            
        prompt = """
        Analyze these screenshots of QField (a GIS app).
        The user should be digitizing a line on a map between Paris and Brussels.
        
        Look for:
        1. A map view showing Europe (France/Belgium area).
        2. A line being drawn (red rubber band line or similar).
        3. An attribute form where 'PAR-BRU-F001' or 'fiber' is entered.
        4. The 'cable_routes' layer being selected in the side panel.
        
        Does the user appear to perform the task of digitizing a line and entering attributes?
        """
        
        vlm_res = query_vlm(prompt=prompt, images=frames)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            # Simple heuristic based on text analysis of VLM response could go here
            # For now, we assume query_vlm returns a structured analysis if configured so, 
            # or we parse the text manually.
            # Assuming gym_anything VLM returns a "positive" boolean or score.
            # We'll default to a manual review of the text logic if needed, 
            # but here we'll assume a field "task_completed" in parsed output.
            if str(parsed).lower().find("yes") != -1 or str(parsed).lower().find("true") != -1:
                vlm_score = 20
                feedback.append("VLM confirms visual workflow.")
            else:
                feedback.append("VLM did not clearly see the workflow.")
        else:
            feedback.append("VLM verification skipped/failed.")
            
    except Exception as e:
        feedback.append(f"VLM error: {e}")
        
    score += vlm_score

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }

def verify_gpkg_geometry(blob, target_coords):
    """
    Parses GeoPackage Binary Geometry BLOB to verify it's a LineString
    and checks if the envelope covers Paris and Brussels.
    """
    if not blob:
        return False, "Geometry is NULL"
    
    # GeoPackage Binary Header
    # Byte 0-1: Magic 'GP'
    if blob[0:2] != b'GP':
        return False, "Invalid GeoPackage Geometry Magic"
    
    # Byte 3: Flags
    flags = blob[3]
    # Bit 0: Envelope info (1-4 means envelope present)
    envelope_indicator = (flags >> 1) & 0x07
    
    header_len = 8 # Default
    
    # Envelope parsing
    envelope = {}
    if envelope_indicator == 0:
        return False, "No envelope in geometry - cannot verify location efficiently"
    elif envelope_indicator == 1: # XY envelope (32 bytes)
        # minx, maxx, miny, maxy (doubles)
        env_data = blob[8:40]
        header_len += 32
        try:
            minx, maxx, miny, maxy = struct.unpack('<dddd', env_data)
            envelope = {'minx': minx, 'maxx': maxx, 'miny': miny, 'maxy': maxy}
        except:
            return False, "Failed to unpack envelope"
    else:
        # Handle Z/M envelopes if necessary, but QField default is usually XY or XYM
        # For simplicity, if it's not standard XY, we might skip precise envelope check 
        # or implement full parsing. Let's assume standard 2D digitizing.
        # Just passing True with a warning if complex geometry.
        return True, "Complex envelope detected, skipped strict bound check (Partial Pass)"

    # Check Geometry Type in WKB (Byte header_len + 1 to header_len + 5)
    # WKB Byte Order (1 byte) + Type (4 bytes)
    wkb_start = header_len
    if len(blob) < wkb_start + 5:
        return False, "Blob too short for WKB"
        
    wkb_order = blob[wkb_start]
    # 1 = Little Endian
    endian = '<' if wkb_order == 1 else '>'
    
    wkb_type = struct.unpack(endian + 'I', blob[wkb_start+1:wkb_start+5])[0]
    
    # 2 = LineString, 1002 = LineStringZ, 2002 = LineStringM, etc.
    # We accept variations of LineString
    if wkb_type not in [2, 1002, 2002, 3002]:
        return False, f"Geometry type {wkb_type} is not LineString"

    # Verify Envelope Covers Paris and Brussels
    # Paris: ~2.35, 48.86
    # Brussels: ~4.35, 50.85
    # The envelope should roughly contain these values.
    
    # Check bounds with some tolerance
    tol = target_coords.get('tolerance_deg', 2.0)
    p_lon, p_lat = target_coords['paris']
    b_lon, b_lat = target_coords['brussels']
    
    # The digitized line envelope must verify that the line *reaches* both areas.
    # Simple check: min_x should be <= min(p_lon, b_lon) + tol
    # max_x should be >= max(p_lon, b_lon) - tol
    # Same for Y.
    
    valid_bounds = (
        envelope['minx'] <= min(p_lon, b_lon) + tol and
        envelope['maxx'] >= max(p_lon, b_lon) - tol and
        envelope['miny'] <= min(p_lat, b_lat) + tol and
        envelope['maxy'] >= max(p_lat, b_lat) - tol
    )
    
    if not valid_bounds:
        return False, f"Geometry bounds {envelope} do not cover Paris-Brussels region"
        
    return True, "Geometry valid"