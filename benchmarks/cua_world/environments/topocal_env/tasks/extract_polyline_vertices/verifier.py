#!/usr/bin/env python3
"""
Verifier for extract_polyline_vertices@1

Multi-signal verification strategy:
1. File Checks: Verifies anti-gaming timestamps and that required files were exported.
2. Coordinate Parsing: Extracts numeric data from the agent's CSV.
3. Geometric Match: Compares the extracted X/Y coordinates against the hidden DXF ground truth.
4. Interpolation Check: Penalizes if the agent generated MORE points than vertices.
5. VLM Trajectory Check: Validates TopoCal was actively used to import the DXF.
"""

import os
import re
import math
import json
import tempfile
import logging
from typing import List, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_csv_for_coordinates(filepath: str) -> List[Tuple[float, float]]:
    """Attempt to flexibly parse coordinates from a potentially messy CSV."""
    coords = []
    # Match lines that have at least 2 distinct floating point numbers (X, Y)
    num_pattern = re.compile(r'-?\d+\.\d+|-?\d+')
    
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            for line in f:
                # Replace common European decimal separators if standard parsing fails
                clean_line = line.strip().replace(',', ' , ')
                numbers = [float(n) for n in num_pattern.findall(clean_line)]
                
                # Check combinations for values matching roughly our local coordinate space
                # Assuming X and Y will be around 900-1100 based on our GT DXF
                valid_pair = None
                for i in range(len(numbers) - 1):
                    x, y = numbers[i], numbers[i+1]
                    if 900 < x < 1100 and 900 < y < 1100:
                        valid_pair = (x, y)
                        break
                
                if valid_pair:
                    coords.append(valid_pair)
    except Exception as e:
        logger.error(f"Error parsing CSV: {e}")
        
    return coords

def verify_extract_polyline_vertices(traj, env_info, task_info):
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable."}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth_vertices', [])
    expected_count = metadata.get('expected_vertex_count', 8)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve metadata result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task status: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence and Timestamps
    if result.get('top_exists') and result.get('top_created_during_task'):
        score += 10
        feedback_parts.append("Project saved properly.")
    else:
        feedback_parts.append("Project (.top) not saved or stale.")

    csv_exists = result.get('csv_exists', False)
    csv_valid_time = result.get('csv_created_during_task', False)
    
    extracted_coords = []
    if csv_exists and csv_valid_time:
        score += 20
        feedback_parts.append("CSV exported successfully.")
        
        # 3. Retrieve and parse the actual CSV
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("C:\\Users\\Docker\\Documents\\stakeout_points.csv", temp_csv.name)
            extracted_coords = parse_csv_for_coordinates(temp_csv.name)
        except Exception as e:
            logger.error(f"Failed to fetch CSV: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    else:
        feedback_parts.append("CSV not found or timestamp invalid.")

    # 4. Geometric & Counting Match
    if len(extracted_coords) > 0:
        # Match points against ground truth (tolerance 0.05 to allow for text-based export rounding)
        matched_gt = set()
        for ex_x, ex_y in extracted_coords:
            for i, (gt_x, gt_y) in enumerate(ground_truth):
                if math.hypot(ex_x - gt_x, ex_y - gt_y) < 0.05:
                    matched_gt.add(i)
        
        match_ratio = len(matched_gt) / expected_count
        acc_score = int(match_ratio * 40)
        score += acc_score
        
        if acc_score == 40:
            feedback_parts.append(f"Coordinate accuracy excellent ({len(matched_gt)}/{expected_count} matched).")
        else:
            feedback_parts.append(f"Coordinate accuracy partial ({len(matched_gt)}/{expected_count} matched).")

        # Did they incorrectly interpolate? (Critical limitation check)
        if len(extracted_coords) == expected_count:
            score += 10
            feedback_parts.append("Exact vertex count respected (no interpolation).")
        else:
            feedback_parts.append(f"Interpolation detected/Missed Points: Found {len(extracted_coords)} points vs {expected_count} expected.")
    else:
        if csv_exists:
            feedback_parts.append("CSV existed but no valid numeric coordinates were parsed.")

    # 5. VLM Trajectory Verification
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            
            prompt = """Analyze these sequence of screenshots from a topographic CAD software (TopoCal).
            1. Did the user import and display a 2D line/polygon representing a building footprint?
            2. Is there visual evidence of points/nodes being generated on the corners of the geometry?
            Answer in JSON: {"imported_geometry": true/false, "points_visible": true/false}"""
            
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('imported_geometry'):
                    vlm_score += 10
                if parsed.get('points_visible'):
                    vlm_score += 10
                    
            if vlm_score > 0:
                feedback_parts.append("VLM confirmed visual CAD interaction.")
            score += vlm_score
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            
    passed = score >= 70 and (len(extracted_coords) > 0)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }