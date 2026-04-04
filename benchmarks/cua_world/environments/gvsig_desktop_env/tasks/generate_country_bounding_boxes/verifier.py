#!/usr/bin/env python3
"""
Verifier for generate_country_bounding_boxes task.

Verification Logic:
1. File Existence: Checks for .shp and .dbf files.
2. Anti-Gaming: Checks creation timestamp vs task start.
3. Feature Count: Parses .dbf header to ensure 177 features (matches input).
4. Geometry Simplification: Checks .shp file size.
   - Original countries: ~5MB (complex polygons)
   - Bounding boxes: < 500KB (simple 5-point polygons)
5. VLM Verification: Checks trajectory for visual confirmation of rectangles.
"""

import json
import os
import struct
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bounding_boxes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_feature_count', 177)
    max_size = metadata.get('max_file_size_bytes', 500000)  # 500KB
    
    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Result Metadata
    # ------------------------------------------------------------------
    result_json_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            res = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(result_json_path):
            os.remove(result_json_path)

    # ------------------------------------------------------------------
    # 2. Verify File Existence & Anti-Gaming (30 pts)
    # ------------------------------------------------------------------
    if res.get('output_shp_exists') and res.get('output_dbf_exists'):
        if res.get('file_created_during_task'):
            score += 30
            feedback_parts.append("Output shapefile created successfully.")
        else:
            score += 10
            feedback_parts.append("Output file exists but timestamp is suspicious (not created during task).")
    else:
        return {"passed": False, "score": 0, "feedback": "Output shapefile not found."}

    # ------------------------------------------------------------------
    # 3. Verify Geometry Simplification via File Size (30 pts)
    # ------------------------------------------------------------------
    # Bounding boxes are simple rectangles (5 points), original is complex.
    # File size should be significantly smaller than original (~5MB).
    shp_size = res.get('shp_size_bytes', 0)
    if 1000 < shp_size < max_size:
        score += 30
        feedback_parts.append(f"Geometry simplified (Size: {shp_size/1024:.1f}KB).")
    elif shp_size >= max_size:
        # If too big, they probably just copied the original file
        feedback_parts.append(f"File too large ({shp_size/1024:.1f}KB). Did you just copy the original layer?")
    else:
        feedback_parts.append("File suspiciously small (empty?).")

    # ------------------------------------------------------------------
    # 4. Verify Feature Count from DBF (20 pts)
    # ------------------------------------------------------------------
    # Retrieve DBF file to check record count
    dbf_local_path = tempfile.mktemp(suffix='.dbf')
    actual_count = -1
    try:
        copy_from_env(metadata['expected_dbf_path'], dbf_local_path)
        
        # Parse DBF Header
        # Bytes 4-7: Number of records (32-bit int, little-endian)
        with open(dbf_local_path, 'rb') as dbf:
            dbf.seek(4)
            data = dbf.read(4)
            if len(data) == 4:
                actual_count = struct.unpack('<I', data)[0]
        
        if actual_count == expected_count:
            score += 20
            feedback_parts.append(f"Correct feature count ({actual_count}).")
        else:
            feedback_parts.append(f"Incorrect feature count: {actual_count} (Expected: {expected_count}).")
            
    except Exception as e:
        feedback_parts.append(f"Failed to verify DBF content: {str(e)}")
    finally:
        if os.path.exists(dbf_local_path):
            os.remove(dbf_local_path)

    # ------------------------------------------------------------------
    # 5. VLM Visual Verification (20 pts)
    # ------------------------------------------------------------------
    # Check if we see rectangular shapes in the final view
    frames = sample_trajectory_frames(traj, n=3)
    final_img = get_final_screenshot(traj)
    
    if final_img:
        prompt = (
            "Review the final screenshot of a GIS application. "
            "The task was to generate bounding boxes for countries. "
            "Do you see a map displaying simple rectangular/boxy shapes covering land masses, "
            "or do you see complex coastlines? "
            "Answer 'YES' if you see rectangular/boxy geometries overlaid on the map."
        )
        
        # Simple VLM check
        vlm_result = query_vlm(images=[final_img], prompt=prompt).strip().upper()
        
        if "YES" in vlm_result:
            score += 20
            feedback_parts.append("Visual verification passed (Rectangles visible).")
        else:
            feedback_parts.append("Visual verification failed (Rectangles not clearly visible).")
    else:
        feedback_parts.append("No final screenshot available for visual verification.")

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    passed = score >= 80 and actual_count == expected_count
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }