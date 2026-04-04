#!/usr/bin/env python3
"""
Verifier for extract_country_boundaries task.
Checks if the output shapefile exists, was created during the task,
and most importantly, contains Polyline geometry (not Polygon).
"""

import os
import json
import struct
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_country_boundaries(traj, env_info, task_info):
    """
    Verifies that the agent converted polygons to lines.
    
    Criteria:
    1. Output shapefile exists.
    2. Output shapefile was created during the task (anti-gaming).
    3. Geometry type in SHP header is Polyline (Type 3).
    4. Feature count in DBF header is reasonable (>150).
    5. VLM confirms tool usage via trajectory.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load metadata
    expected_geom_type = task_info.get('metadata', {}).get('expected_geometry_type', 3) # 3 = Polyline
    min_feature_count = task_info.get('metadata', {}).get('min_feature_count', 150)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Get Result JSON
    # ------------------------------------------------------------------
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as f:
            copy_from_env("/tmp/task_result.json", f.name)
            with open(f.name, 'r') as json_f:
                result = json.load(json_f)
            os.unlink(f.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

    shp_path = result.get("output_shp_path")
    dbf_path = result.get("output_dbf_path")
    
    if not result.get("shp_exists") or not result.get("dbf_exists"):
        return {"passed": False, "score": 0, "feedback": "Output shapefile/dbf not found."}

    # Anti-gaming check
    if result.get("shp_created_during_task"):
        score += 10
        feedback_parts.append("File created during task session.")
    else:
        feedback_parts.append("Warning: Output file is old (pre-existing).")

    # ------------------------------------------------------------------
    # 2. Binary Shapefile Analysis (Geometry Type)
    # ------------------------------------------------------------------
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".shp") as shp_tmp:
            copy_from_env(shp_path, shp_tmp.name)
            with open(shp_tmp.name, "rb") as f:
                # Shapefile Header is 100 bytes
                # Byte 32-35 is Shape Type (Little Endian Integer)
                f.seek(32)
                type_bytes = f.read(4)
                shape_type = struct.unpack('<i', type_bytes)[0]
            os.unlink(shp_tmp.name)

        # 3 = Polyline, 13 = PolylineZ, 23 = PolylineM
        # 5 = Polygon (which would verify FAIL if they just copied the file)
        if shape_type in [3, 13, 23]:
            score += 40
            feedback_parts.append("Success: Output geometry is Polyline.")
        elif shape_type == 5:
            feedback_parts.append("Fail: Output geometry is still Polygon (did you just copy the layer?).")
        else:
            feedback_parts.append(f"Fail: Unexpected geometry type code: {shape_type}.")

    except Exception as e:
        feedback_parts.append(f"Error parsing shapefile: {str(e)}")

    # ------------------------------------------------------------------
    # 3. DBF Analysis (Feature Count)
    # ------------------------------------------------------------------
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".dbf") as dbf_tmp:
            copy_from_env(dbf_path, dbf_tmp.name)
            with open(dbf_tmp.name, "rb") as f:
                # DBF Header
                # Byte 4-7: Number of records (Little Endian Integer)
                f.seek(4)
                count_bytes = f.read(4)
                record_count = struct.unpack('<I', count_bytes)[0]
            os.unlink(dbf_tmp.name)
        
        if record_count >= min_feature_count:
            score += 20
            feedback_parts.append(f"Data integrity verified: {record_count} features.")
        else:
            feedback_parts.append(f"Data loss warning: Only {record_count} features found (expected >{min_feature_count}).")

    except Exception as e:
        feedback_parts.append(f"Error parsing DBF: {str(e)}")

    # ------------------------------------------------------------------
    # 4. VLM Verification (Trajectory)
    # ------------------------------------------------------------------
    # We check if the agent actually opened the Geoprocessing toolbox
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    prompt = """
    Review this sequence of screenshots from gvSIG Desktop.
    The user task was to convert a Polygon layer to Lines using Geoprocessing tools.
    
    Look for:
    1. The 'Geoprocessing' toolbox or menu being opened.
    2. A dialog titled 'Polygons to lines' or similar.
    3. The final map showing line geometries (hollow borders) rather than filled polygons.
    
    Return JSON: {"geoprocessing_opened": bool, "tool_used": bool, "final_layer_looks_correct": bool}
    """
    
    try:
        vlm_res = query_vlm(frames + [final_screen], prompt, output_schema={
            "geoprocessing_opened": "bool",
            "tool_used": "bool",
            "final_layer_looks_correct": "bool"
        })
        
        if vlm_res.get("geoprocessing_opened") or vlm_res.get("tool_used"):
            score += 15
            feedback_parts.append("VLM confirmed Geoprocessing tool usage.")
        
        if vlm_res.get("final_layer_looks_correct"):
            score += 15
            feedback_parts.append("VLM confirmed visual correctness.")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Graceful fallback: if file checks passed, give partial credit
        if score >= 60:
            score += 10
            feedback_parts.append("Skipped VLM check (error), checking file validity only.")

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    passed = (score >= 70) and ("Output geometry is Polyline" in str(feedback_parts))
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }