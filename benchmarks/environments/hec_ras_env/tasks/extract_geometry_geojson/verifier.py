#!/usr/bin/env python3
"""
Verifier for extract_geometry_geojson task.
Parses the agent's GeoJSON output and compares it against ground truth 
extracted directly from the .g04 source file.
"""

import json
import os
import logging
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_hec_ras_g04(file_path):
    """
    Mini-parser for HEC-RAS .g04 geometry files.
    Extracts Reach XY and XS GIS Cut Lines.
    Returns a dictionary with parsed features.
    """
    features = {
        "reaches": [],
        "cross_sections": []
    }
    
    current_reach = None
    current_xs = None
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
            
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            
            # 1. Reach XY Extraction
            if line.startswith("Reach XY="):
                # Format: Reach XY= [number of points]
                try:
                    num_points = int(line.split('=')[1].strip())
                    points = []
                    i += 1
                    
                    # Read coordinate lines until we have enough points
                    while len(points) < num_points * 2 and i < len(lines):
                        # HEC-RAS stores coords as X Y X Y ...
                        # Each line is fixed width or space delimited. 
                        # Usually 16 chars per field, but split helps.
                        coords_on_line = lines[i].strip().split()
                        points.extend([float(c) for c in coords_on_line])
                        i += 1
                    
                    # Convert [x1, y1, x2, y2...] to [(x1,y1), (x2,y2)...]
                    coords = []
                    for k in range(0, len(points), 2):
                        if k+1 < len(points):
                            coords.append((points[k], points[k+1]))
                            
                    features["reaches"].append({
                        "coords": coords,
                        "count": num_points
                    })
                    continue # Already incremented i
                except Exception as e:
                    logger.warning(f"Error parsing Reach XY at line {i}: {e}")

            # 2. Cross Section Cut Line Extraction
            elif line.startswith("XS GIS Cut Line="):
                try:
                    num_points = int(line.split('=')[1].strip())
                    points = []
                    i += 1
                    
                    while len(points) < num_points * 2 and i < len(lines):
                        coords_on_line = lines[i].strip().split()
                        points.extend([float(c) for c in coords_on_line])
                        i += 1
                        
                    coords = []
                    for k in range(0, len(points), 2):
                        if k+1 < len(points):
                            coords.append((points[k], points[k+1]))
                    
                    # Try to find the Station for this XS (it usually appears earlier in "Type RM Length L Ch R = ...")
                    # But verifying just geometry existence and approximate count is sufficient for this task
                    features["cross_sections"].append({
                        "coords": coords,
                        "count": num_points
                    })
                    continue
                except Exception as e:
                    logger.warning(f"Error parsing XS Cut Line at line {i}: {e}")
            
            i += 1
            
    except Exception as e:
        logger.error(f"Failed to parse .g04 file: {e}")
        return None

    return features

def verify_extract_geometry_geojson(traj, env_info, task_info):
    """
    Verifies the generated GeoJSON against the input .g04 file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check existence
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output GeoJSON file was not created."}

    # 2. Retrieve Agent Output and Ground Truth Input
    agent_output_path = result_data.get("output_path_in_container")
    ground_truth_input_path = result_data.get("input_path_in_container")
    
    local_agent_geojson = tempfile.mktemp(suffix='.geojson')
    local_ground_truth = tempfile.mktemp(suffix='.g04')
    
    score = 0
    feedback_parts = []
    
    try:
        copy_from_env(agent_output_path, local_agent_geojson)
        copy_from_env(ground_truth_input_path, local_ground_truth)
        
        # 3. Parse Ground Truth
        gt_features = parse_hec_ras_g04(local_ground_truth)
        if not gt_features:
            return {"passed": False, "score": 0, "feedback": "Verifier failed to parse ground truth .g04 file."}
        
        gt_reach_count = len(gt_features["reaches"])
        gt_xs_count = len(gt_features["cross_sections"])
        
        # 4. Parse Agent GeoJSON
        with open(local_agent_geojson, 'r') as f:
            geojson_data = json.load(f)
            
        if geojson_data.get("type") != "FeatureCollection":
            return {"passed": False, "score": 0, "feedback": "Output is not a valid GeoJSON FeatureCollection."}
            
        agent_features = geojson_data.get("features", [])
        
        # Categorize agent features
        agent_reaches = [f for f in agent_features if f.get("properties", {}).get("type") == "reach"]
        agent_xs = [f for f in agent_features if f.get("properties", {}).get("type") == "cross_section"]
        
        # Fallback: if type property missing, guess by geometry type or assumption
        if not agent_reaches and not agent_xs:
            # Maybe they didn't use the 'type' property correctly?
            # Reaches are usually longer, but let's just count LineStrings
            lines = [f for f in agent_features if f.get("geometry", {}).get("type") == "LineString"]
            # Assume strict requirement for 'type' property as per task desc
            feedback_parts.append("WARNING: Features missing 'type' property ('reach' or 'cross_section').")
        
        # --- SCORING ---
        
        # Criterion 1: Valid GeoJSON structure (20 pts)
        score += 20
        feedback_parts.append("Valid GeoJSON file.")
        
        # Criterion 2: Reach Count (20 pts)
        if len(agent_reaches) == gt_reach_count:
            score += 20
            feedback_parts.append(f"Correct reach count ({len(agent_reaches)}).")
        elif len(agent_reaches) > 0:
            score += 10
            feedback_parts.append(f"Reach found but count mismatch (Found {len(agent_reaches)}, Expected {gt_reach_count}).")
        else:
            feedback_parts.append("No features with type='reach' found.")
            
        # Criterion 3: Cross-Section Count (20 pts)
        # Allow small tolerance
        tolerance = max(2, int(gt_xs_count * 0.05))
        if abs(len(agent_xs) - gt_xs_count) <= tolerance:
            score += 20
            feedback_parts.append(f"Correct XS count ({len(agent_xs)} vs {gt_xs_count}).")
        elif len(agent_xs) > 0:
            score += 10
            feedback_parts.append(f"XS count mismatch (Found {len(agent_xs)}, Expected {gt_xs_count}).")
        else:
            feedback_parts.append("No features with type='cross_section' found.")
            
        # Criterion 4: Coordinate Accuracy (20 pts)
        # Check first reach coordinates
        coord_match = False
        if gt_features["reaches"] and agent_reaches:
            gt_coords = gt_features["reaches"][0]["coords"]
            # Get agent coords (LineString is list of points)
            agent_coords = agent_reaches[0].get("geometry", {}).get("coordinates", [])
            
            # Compare first and last point
            if len(gt_coords) > 0 and len(agent_coords) > 0:
                # Euclidean distance check for start/end
                d_start = math.hypot(gt_coords[0][0] - agent_coords[0][0], gt_coords[0][1] - agent_coords[0][1])
                d_end = math.hypot(gt_coords[-1][0] - agent_coords[-1][0], gt_coords[-1][1] - agent_coords[-1][1])
                
                if d_start < 1.0 and d_end < 1.0: # 1.0 unit tolerance
                    coord_match = True
        
        if coord_match:
            score += 20
            feedback_parts.append("Reach coordinates match ground truth.")
        else:
            feedback_parts.append("Reach coordinates do not match ground truth.")

        # Criterion 5: Metadata (20 pts)
        # Check for required properties keys
        required_keys = ["river_name", "reach_name", "station"]
        metadata_ok = False
        if agent_xs:
            props = agent_xs[0].get("properties", {})
            if all(key in props for key in required_keys):
                metadata_ok = True
        
        if metadata_ok:
            score += 20
            feedback_parts.append("Metadata properties found.")
        else:
            feedback_parts.append("Missing required metadata properties.")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification error: {e}"}
    finally:
        # Cleanup
        if os.path.exists(local_agent_geojson):
            os.unlink(local_agent_geojson)
        if os.path.exists(local_ground_truth):
            os.unlink(local_ground_truth)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }