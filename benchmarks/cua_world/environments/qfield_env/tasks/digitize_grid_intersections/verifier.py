#!/usr/bin/env python3
import json
import struct
import math
import os
import tempfile
import logging
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_geopackage_point(hex_string: str) -> Optional[List[float]]:
    """
    Parses a GeoPackage Binary Geometry Blob (Header + WKB) to extract Point coordinates.
    Returns [x, y] or None if invalid/not a point.
    
    See OGC GeoPackage Encoding Standard.
    """
    try:
        # Convert hex to bytes
        blob = bytes.fromhex(hex_string)
        
        # Header is at least 8 bytes (2 magic + 1 version + 1 flags + 4 srs_id)
        if len(blob) < 8:
            return None
            
        # Magic "GP" (0x47 0x50)
        if blob[0] != 0x47 or blob[1] != 0x50:
            return None
            
        # Version 0
        if blob[2] != 0:
            return None
            
        # Flags (byte 3)
        flags = blob[3]
        # Bit 0: Envelope check (0=no envelope, 1-4=envelope types)
        # Bit 5: Binary type (0=Standard, 1=Extended)
        # Bit 4: Empty geometry
        
        if (flags & (1 << 4)): # Empty geometry
            return None
            
        envelope_indicator = (flags >> 1) & 0x07
        header_len = 8 # Base header
        
        # Add envelope length
        if envelope_indicator == 1:
            header_len += 32
        elif envelope_indicator == 2:
            header_len += 48
        elif envelope_indicator == 3:
            header_len += 48
        elif envelope_indicator == 4:
            header_len += 64
            
        # WKB starts after header
        wkb = blob[header_len:]
        
        # Parse WKB Point
        # Byte order (1 byte): 0=Big Endian, 1=Little Endian
        byte_order = wkb[0]
        endian = '<' if byte_order == 1 else '>'
        
        # Geometry Type (4 bytes)
        geom_type = struct.unpack(f'{endian}I', wkb[1:5])[0]
        
        # Point type is 1 (or 1001/2001/3001 for various dims)
        # We assume 2D point for this task
        if geom_type != 1: 
            return None
            
        # Coordinates (2 doubles = 16 bytes)
        x, y = struct.unpack(f'{endian}dd', wkb[5:21])
        return [x, y]
        
    except Exception as e:
        logger.error(f"Error parsing geometry: {e}")
        return None

def calculate_distance(p1, p2):
    """Euclidean distance for simple coordinate check."""
    return math.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)

def verify_grid_intersections(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that the agent created two points at the correct grid intersections.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', {})
    
    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initial scoring setup
    score = 0
    feedback = []
    
    features = result_data.get('features', [])
    file_modified = result_data.get('file_modified', False)
    
    if not file_modified:
        feedback.append("GeoPackage file was not modified (do nothing detected).")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}
        
    if not features:
        feedback.append("No features found matching the required names.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Evaluate Station_North
    north_target = targets.get('Station_North', {})
    north_feature = next((f for f in features if 'Station_North' in f.get('name', '')), None)
    
    if north_feature:
        score += 10 # Feature exists
        
        # Check Notes
        if 'Oslo' in north_feature.get('notes', '') and 'Rome' in north_feature.get('notes', ''):
            score += 10
            
        # Check Geometry
        geom = parse_geopackage_point(north_feature.get('geom_hex', ''))
        if geom:
            expected = [north_target['expected_lon'], north_target['expected_lat']]
            dist = calculate_distance(geom, expected)
            
            if dist <= north_target['tolerance']:
                score += 30
                feedback.append(f"Station_North placed correctly (dist: {dist:.4f}).")
            else:
                feedback.append(f"Station_North placement too far off (dist: {dist:.4f}, expected {expected}).")
        else:
            feedback.append("Station_North geometry invalid.")
    else:
        feedback.append("Station_North feature missing.")

    # Evaluate Station_South
    south_target = targets.get('Station_South', {})
    south_feature = next((f for f in features if 'Station_South' in f.get('name', '')), None)
    
    if south_feature:
        score += 10 # Feature exists
        
        # Check Notes
        if 'Cape Town' in south_feature.get('notes', '') and 'Cairo' in south_feature.get('notes', ''):
            score += 10
            
        # Check Geometry
        geom = parse_geopackage_point(south_feature.get('geom_hex', ''))
        if geom:
            expected = [south_target['expected_lon'], south_target['expected_lat']]
            dist = calculate_distance(geom, expected)
            
            if dist <= south_target['tolerance']:
                score += 30
                feedback.append(f"Station_South placed correctly (dist: {dist:.4f}).")
            else:
                feedback.append(f"Station_South placement too far off (dist: {dist:.4f}, expected {expected}).")
        else:
            feedback.append("Station_South geometry invalid.")
    else:
        feedback.append("Station_South feature missing.")

    # VLM Trajectory Verification
    # (Optional but good for anti-gaming - check if they actually navigated)
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Does the agent appear to be using a map application (QField)? "
            "Do you see interactions with map markers or feature forms? "
            "Return JSON: {\"is_map_app\": bool, \"marker_interaction\": bool}"
        )
        try:
            vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('is_map_app'):
                    # Bonus for visual confirmation of work
                    # We don't fail based on this alone to avoid VLM flakiness, but we check it
                    pass
        except:
            pass

    passed = score >= 60 # Must get at least one station roughly right or both partially right
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }