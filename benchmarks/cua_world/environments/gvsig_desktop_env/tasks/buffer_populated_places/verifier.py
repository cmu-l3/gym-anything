#!/usr/bin/env python3
"""
Verifier for gvSIG buffer_populated_places task.

Verifies:
1. Existence of output Shapefile and sidecars (.dbf, .shx)
2. Creation timestamp (must be during task)
3. Shapefile geometry type (must be Polygon = 5)
4. Record count (must be reasonable for the input dataset)
5. Visual verification via VLM (trajectory analysis)
"""

import json
import os
import struct
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_shapefile_header(shp_path):
    """
    Parses the binary header of a .shp file to get the shape type.
    Byte 32-35: Shape Type (Little Endian Integer)
    Values: 1=Point, 3=PolyLine, 5=Polygon, 15=PolygonZ
    """
    try:
        with open(shp_path, 'rb') as f:
            # Seek to Shape Type position (byte 32)
            f.seek(32)
            shape_type_bytes = f.read(4)
            if len(shape_type_bytes) < 4:
                return None
            # Unpack little-endian integer
            shape_type = struct.unpack('<i', shape_type_bytes)[0]
            return shape_type
    except Exception as e:
        logger.error(f"Error parsing SHP header: {e}")
        return None

def parse_dbf_record_count(dbf_path):
    """
    Parses the binary header of a .dbf file to get the record count.
    Byte 4-7: Number of records (Little Endian Integer)
    """
    try:
        with open(dbf_path, 'rb') as f:
            f.seek(4)
            count_bytes = f.read(4)
            if len(count_bytes) < 4:
                return None
            count = struct.unpack('<I', count_bytes)[0]
            return count
    except Exception as e:
        logger.error(f"Error parsing DBF header: {e}")
        return None

def verify_buffer_populated_places(traj, env_info, task_info):
    """
    Verify that the agent created a buffer polygon shapefile.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Check file existence and timestamp (Anti-Gaming)
    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output shapefile not found."}
    
    score += 15
    feedback_parts.append("Output file exists")
    
    if created_during_task:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File NOT created during task (timestamp mismatch)")
        # If file existed before, it's a fail on anti-gaming
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Retrieve actual Shapefile and DBF for binary verification
    output_path_remote = result.get('output_path')
    dbf_path_remote = result.get('dbf_path')
    
    temp_shp = tempfile.NamedTemporaryFile(delete=False, suffix='.shp')
    temp_dbf = tempfile.NamedTemporaryFile(delete=False, suffix='.dbf')
    
    try:
        copy_from_env(output_path_remote, temp_shp.name)
        copy_from_env(dbf_path_remote, temp_dbf.name)
        
        # Verify Geometry Type
        shape_type = parse_shapefile_header(temp_shp.name)
        # 5 = Polygon, 15 = PolygonZ (buffer usually creates Polygon)
        if shape_type in [5, 15]:
            score += 20
            feedback_parts.append(f"Valid Polygon Geometry (Type {shape_type})")
        else:
            feedback_parts.append(f"Invalid Geometry Type: {shape_type} (Expected 5 or 15)")
            
        # Verify Record Count
        # Input has ~243 records. Output should have roughly the same.
        record_count = parse_dbf_record_count(temp_dbf.name)
        min_count = metadata.get('min_feature_count', 50)
        
        if record_count is not None and record_count >= min_count:
            score += 20
            feedback_parts.append(f"Record count valid ({record_count} features)")
        else:
            feedback_parts.append(f"Record count too low: {record_count}")

    except Exception as e:
        feedback_parts.append(f"Failed to verify file content: {e}")
    finally:
        if os.path.exists(temp_shp.name): os.unlink(temp_shp.name)
        if os.path.exists(temp_dbf.name): os.unlink(temp_dbf.name)

    # 4. VLM Trajectory Verification
    # Check if the agent actually used the geoprocessing tool interface
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        if frames:
            prompt = """
            Analyze these screenshots of a GIS task in gvSIG Desktop.
            The user was supposed to:
            1. Load a points layer (cities).
            2. Open the 'Buffer' geoprocessing tool.
            3. Run the buffer tool to create polygons.

            Look for:
            - A dialog box titled "Buffer" or "Geoprocessing".
            - A map view showing point data initially.
            - A map view showing circular/polygon buffers around points in the final state.

            Return JSON:
            {
                "tool_dialog_visible": true/false,
                "points_visible": true/false,
                "buffers_visible": true/false,
                "score": 0-35
            }
            """
            
            vlm_response = query_vlm(images=frames + [final_img], prompt=prompt)
            vlm_data = {}
            try:
                # Extract JSON from response if wrapped in backticks
                content = vlm_response.strip()
                if "