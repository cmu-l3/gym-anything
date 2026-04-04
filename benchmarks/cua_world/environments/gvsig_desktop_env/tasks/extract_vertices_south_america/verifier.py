#!/usr/bin/env python3
"""
Verifier for extract_vertices_south_america task.

Verifies:
1. Shapefile creation and freshness.
2. Shapefile geometry type (must be Point or MultiPoint).
3. Spatial extent (Bounding Box) to confirm only South America was selected.
4. VLM verification of the process (selection and tool usage).

Note: This verifier runs on the HOST. It parses the binary Shapefile header
using python's `struct` module to avoid heavy GIS dependencies like GDAL.
"""

import json
import os
import struct
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_shp_header(shp_path):
    """
    Parses the standard 100-byte Shapefile header.
    Ref: http://www.esri.com/library/whitepapers/pdfs/shapefile.pdf
    """
    try:
        with open(shp_path, 'rb') as f:
            header_data = f.read(100)
            
        if len(header_data) < 100:
            return None
            
        # Unpack header
        # Byte 0-3: File Code (9994) - Big Endian
        # Byte 32-35: Shape Type - Little Endian
        # Byte 36-67: Bounding Box (Xmin, Ymin, Xmax, Ymax) - Little Endian Doubles
        
        file_code = struct.unpack('>I', header_data[0:4])[0]
        if file_code != 9994:
            return None
            
        shape_type = struct.unpack('<i', header_data[32:36])[0]
        bbox = struct.unpack('<4d', header_data[36:68]) # xmin, ymin, xmax, ymax
        
        return {
            "valid_shp": True,
            "shape_type": shape_type,
            "bbox": {
                "xmin": bbox[0],
                "ymin": bbox[1],
                "xmax": bbox[2],
                "ymax": bbox[3]
            }
        }
    except Exception as e:
        logger.error(f"Error parsing SHP header: {e}")
        return None

def verify_extract_vertices_south_america(traj, env_info, task_info):
    """
    Verifies that vertices were extracted specifically for South America.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Load basic task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 2. Verify File Existence and Creation (30 pts)
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    file_size = result.get('file_size', 0)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output shapefile 'sa_vertices.shp' was not found."}
    
    if created_during:
        score += 30
        feedback.append("Output file created during task.")
    else:
        feedback.append("Output file exists but timestamp indicates it wasn't created during this run.")
        # Continue but no points for creation

    if file_size < 1000: # Shapefile header is 100 bytes, plus records. A valid extract should be >1KB.
        feedback.append(f"Warning: File size is very small ({file_size} bytes). Possibly empty.")
    
    # 3. Analyze Shapefile Content (Geometry & BBox) (40 pts)
    shp_valid = False
    bbox_correct = False
    
    temp_shp = tempfile.NamedTemporaryFile(delete=False, suffix='.shp')
    try:
        copy_from_env("/tmp/sa_vertices.shp", temp_shp.name)
        shp_info = parse_shp_header(temp_shp.name)
        
        if shp_info and shp_info.get('valid_shp'):
            # Check Geometry Type (1=Point, 8=MultiPoint, 11=PointZ, 21=PointM, etc)
            stype = shp_info['shape_type']
            # Valid point types in SHP spec
            if stype in [1, 8, 11, 21, 28]: 
                score += 20
                feedback.append(f"Correct geometry type (Type {stype}: Point/MultiPoint).")
                shp_valid = True
            elif stype == 5:
                feedback.append("Incorrect geometry type: Output is still Polygons (Type 5). Did not run extraction tool.")
            else:
                feedback.append(f"Incorrect geometry type: {stype}")

            # Check Bounding Box (Spatial Selection Verification)
            # South America approx: X: -82 to -34, Y: -56 to +13
            # Allow buffer: X: -95 to -25, Y: -65 to +20
            # Global would be -180 to 180
            
            bbox = shp_info['bbox']
            xmin, ymin, xmax, ymax = bbox['xmin'], bbox['ymin'], bbox['xmax'], bbox['ymax']
            
            # Simple check: Is it roughly confined to SA?
            is_sa_lon = (-95 <= xmin) and (xmax <= -25)
            is_sa_lat = (-65 <= ymin) and (ymax <= 20)
            
            # Check if it's GLOBAL (failed selection)
            is_global = (xmin < -100) or (xmax > 0) or (ymin < -60) or (ymax > 30)
            
            if is_sa_lon and is_sa_lat:
                score += 20
                bbox_correct = True
                feedback.append("Spatial extent matches South America. Selection was likely correct.")
            elif is_global:
                feedback.append(f"Spatial extent is too large (X:{xmin:.1f} to {xmax:.1f}). Likely failed to select 'South America' or did not check 'Selected features only'.")
            else:
                feedback.append(f"Spatial extent mismatch (X:{xmin:.1f} to {xmax:.1f}, Y:{ymin:.1f} to {ymax:.1f}).")
                
        else:
            feedback.append("Could not parse valid shapefile header.")
            
    except Exception as e:
        feedback.append(f"Error analyzing shapefile: {e}")
    finally:
        if os.path.exists(temp_shp.name):
            os.unlink(temp_shp.name)

    # 4. VLM Trajectory Verification (30 pts)
    # Check if agent was seen selecting features or using the toolbox
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze these screenshots of gvSIG Desktop. "
        "Did the user perform the following steps?\n"
        "1. Select specific countries on the map (highlighted in yellow)?\n"
        "2. Open the Geoprocessing or SEXTANTE toolbox?\n"
        "3. Configure a tool window (like 'Extract nodes' or 'Polygons to points')?\n"
        "4. Did the user ensure 'Selected features only' was checked?\n"
        "Provide a score 0-30 based on evidence of this workflow."
    )
    
    try:
        vlm_result = query_vlm(
            images=frames + [final_frame] if final_frame else frames,
            prompt=vlm_prompt
        )
        
        # Simple heuristic to extract score from VLM (assuming it follows instructions, 
        # but robust verifiers usually use structured output. Here we'll award points 
        # if the VLM response is positive about the workflow).
        vlm_text = vlm_result.lower()
        vlm_score = 0
        if "selected" in vlm_text or "highlighted" in vlm_text:
            vlm_score += 10
        if "toolbox" in vlm_text or "sextante" in vlm_text or "tool" in vlm_text:
            vlm_score += 10
        if "configure" in vlm_text or "check" in vlm_text or "dialog" in vlm_text:
            vlm_score += 10
            
        score += vlm_score
        feedback.append(f"VLM verification score: {vlm_score}/30")
        
    except Exception as e:
        logger.error(f"VLM error: {e}")
        # Fallback points if VLM fails but programmatic checks passed
        if shp_valid and bbox_correct:
            score += 30
            feedback.append("VLM skipped, awarded points based on correct output file.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }