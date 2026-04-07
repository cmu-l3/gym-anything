#!/usr/bin/env python3
"""
Verifier for map_island_logistics_hub task.
Verifies:
1. New feature added to GeoPackage.
2. Feature attributes match requirements.
3. Feature geometry is within Tasmania bounding box.
4. VLM: Background map (OSM) was used/visible.
"""

import json
import os
import tempfile
import struct
import logging
from typing import Dict, Any, Tuple

# Import VLM utils from framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for testing
    def query_vlm(**kwargs): return {"success": False}
    def sample_trajectory_frames(traj, n=1): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_gpkg_point_blob(blob: bytes) -> Tuple[float, float]:
    """
    Parses a GeoPackage Binary Geometry Blob for a Point.
    Ref: http://www.geopackage.org/spec/#gpb_format
    
    Structure:
    - Header (variable length)
      - Magic (2 bytes): 0x47 0x50 ('GP')
      - Version (1 byte): 0
      - Flags (1 byte): 
        - Bit 0: 0=BigEndian, 1=LittleEndian
        - Bit 1-3: Envelope type (0=None)
        - Bit 5: Empty geometry flag
    - SRS ID (4 bytes)
    - Envelope (variable, usually 0 for points if envelope flag is 0)
    - WKBGeometry (Well-Known Binary)
      - ByteOrder (1 byte)
      - wkbType (4 bytes)
      - X (8 bytes double)
      - Y (8 bytes double)
    """
    try:
        if len(blob) < 8:
            return None
        
        # Check magic
        if blob[0:2] != b'GP':
            return None
        
        flags = blob[3]
        # little_endian = (flags & 1) == 1
        envelope_indicator = (flags >> 1) & 0x07
        
        # Determine header length
        header_len = 8 # Magic(2) + Ver(1) + Flags(1) + SRS_ID(4)
        
        envelope_len = 0
        if envelope_indicator == 1: envelope_len = 32
        elif envelope_indicator == 2: envelope_len = 48
        elif envelope_indicator == 3: envelope_len = 48
        elif envelope_indicator == 4: envelope_len = 64
        
        wkb_start = header_len + envelope_len
        wkb = blob[wkb_start:]
        
        # Parse WKB Point
        # Byte 0: Endianness (0=Big, 1=Little)
        # Bytes 1-4: Type (1 = Point)
        # Bytes 5-20: X, Y (doubles)
        
        endian_char = '<' if wkb[0] == 1 else '>'
        wkb_type = struct.unpack(f'{endian_char}I', wkb[1:5])[0]
        
        # 1 = Point, 1001 = PointZ, 2001 = PointM, 3001 = PointZM
        # We assume 2D point for simplicity, or handle 3D by just reading first 2 coords
        if wkb_type in [1, 1001, 2001, 3001]:
            x, y = struct.unpack(f'{endian_char}dd', wkb[5:21])
            return (x, y)
            
    except Exception as e:
        logger.error(f"Error parsing blob: {e}")
    return None

def verify_map_island_logistics_hub(traj, env_info, task_info):
    """
    Verification logic for map_island_logistics_hub.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    bbox = metadata.get('target_bbox', {'min_lat': -44.0, 'max_lat': -40.0, 'min_lon': 144.0, 'max_lon': 149.0})
    target_name = metadata.get('target_name', 'Tasmania Depot')

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON and GeoPackage
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gpkg = tempfile.NamedTemporaryFile(delete=False, suffix='.gpkg')
    
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        copy_from_env("/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg", temp_gpkg.name)
        
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        added_count = result_data.get('added_count', 0)
        
        # Check if feature added
        if added_count > 0:
            score += 20
            feedback_parts.append("New feature created.")
            
            # 2. Verify Attributes
            last_attrs = result_data.get('last_feature_attributes', {})
            if last_attrs and target_name.lower() in last_attrs.get('name', '').lower():
                score += 20
                feedback_parts.append(f"Correct name '{last_attrs.get('name')}'.")
            else:
                feedback_parts.append(f"Incorrect name: '{last_attrs.get('name', 'None')}' (expected '{target_name}').")
                
            # 3. Verify Geometry (Python-side SQLite access)
            try:
                import sqlite3
                conn = sqlite3.connect(temp_gpkg.name)
                cursor = conn.cursor()
                # Get geometry blob of last feature
                cursor.execute("SELECT geom FROM field_observations ORDER BY fid DESC LIMIT 1")
                row = cursor.fetchone()
                if row and row[0]:
                    coords = parse_gpkg_point_blob(row[0])
                    if coords:
                        lon, lat = coords
                        if (bbox['min_lon'] <= lon <= bbox['max_lon']) and (bbox['min_lat'] <= lat <= bbox['max_lat']):
                            score += 40
                            feedback_parts.append(f"Location correct ({lat:.4f}, {lon:.4f}) in Tasmania.")
                        else:
                            feedback_parts.append(f"Location OUT OF BOUNDS ({lat:.4f}, {lon:.4f}). Expected Tasmania.")
                    else:
                        feedback_parts.append("Could not parse geometry.")
                else:
                    feedback_parts.append("No geometry found for feature.")
                conn.close()
            except Exception as e:
                feedback_parts.append(f"Geometry check failed: {str(e)}")
                
        else:
            feedback_parts.append("No new feature created.")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_gpkg.name): os.unlink(temp_gpkg.name)

    # 4. VLM Verification: Check for Basemap Usage
    # We check if screenshots show a map (not just white background)
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    if frames:
        vlm_prompt = """
        Analyze these QField screenshots.
        1. Is a background map visible (satellite imagery, street map tiles, or geography)? 
           Distinguish this from a plain white background with just dots.
        2. Can you see the island of Tasmania (triangular island)?
        3. Is there evidence the user added an 'OpenStreetMap' or similar layer?
        
        Return JSON:
        {
            "background_map_visible": true/false,
            "tasmania_visible": true/false,
            "reasoning": "..."
        }
        """
        
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('background_map_visible', False):
                score += 20
                feedback_parts.append("VLM: Background map confirmed.")
            else:
                feedback_parts.append("VLM: No background map detected (white background only).")
        else:
            # Fallback if VLM fails: give benefit of doubt if geometry was perfect, else 0
            feedback_parts.append("VLM check failed.")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }