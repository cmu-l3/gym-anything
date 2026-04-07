#!/usr/bin/env python3
"""
Verifier for extract_points_from_tin_mesh task.

Verification Strategy:
1. Check if the output CSV was created during the task (anti-gaming).
2. Parse the CSV to extract vertices.
3. Compare extracted vertices to the known ground truth mesh.
4. Verify duplicate cleanup: The raw mesh has 12 points, but only 6 unique spatial locations.
   If the agent exported ~12 points, they failed deduplication.
   If the agent exported exactly 6 points, deduplication succeeded.
5. VLM check on trajectory to ensure TopoCal UI was actually used (prevents python scripting bypass).
"""

import json
import os
import tempfile
import re
import math
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth expected from the synthetic DXF
GROUND_TRUTH_VERTS = [
    (5000.0, 5000.0, 1800.0),
    (5010.0, 5000.0, 1802.0),
    (5020.0, 5000.0, 1801.0),
    (5000.0, 5010.0, 1801.0),
    (5010.0, 5010.0, 1803.0),
    (5020.0, 5010.0, 1804.0)
]

def parse_topocal_csv(filepath):
    """Safely extracts 3D coordinates from a heterogeneous CAD text dump."""
    points = []
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            # Extract all floating point/integer numbers from the line
            nums = re.findall(r"[-+]?\d*\.\d+|\d+", line)
            if len(nums) >= 3:
                try:
                    # Usually CAD exports have X, Y, Z in the middle/end
                    # Find sequences that look like our coordinate space (X~5000, Z~1800)
                    floats = [float(n) for n in nums]
                    for i in range(len(floats) - 2):
                        x, y, z = floats[i], floats[i+1], floats[i+2]
                        if 4900 < x < 5100 and 4900 < y < 5100 and 1700 < z < 1900:
                            points.append((x, y, z))
                            break
                except ValueError:
                    continue
    return points

def verify_extract_points(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve metadata result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\data\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Criteria 1: Output File Exists and was generated during task (Anti-Gaming)
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file was not found."}
    
    if result.get('file_created_during_task', False):
        score += 15
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("Warning: File may have existed prior to task execution")

    # 2. Retrieve the actual CSV file to evaluate geometry
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("C:\\workspace\\data\\extracted_mesh_nodes.csv", temp_csv.name)
        extracted_points = parse_topocal_csv(temp_csv.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve CSV: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    point_count = len(extracted_points)
    
    if point_count == 0:
        return {"passed": False, "score": score, "feedback": "No valid 3D points found in the CSV"}

    # Criteria 2: Spatial Match (Do the points match the DXF mesh corners?)
    matched_gt = 0
    for gt in GROUND_TRUTH_VERTS:
        for pt in extracted_points:
            dist = math.sqrt((gt[0]-pt[0])**2 + (gt[1]-pt[1])**2 + (gt[2]-pt[2])**2)
            if dist < 0.05:  # 5cm tolerance
                matched_gt += 1
                break
                
    coverage_pct = matched_gt / len(GROUND_TRUTH_VERTS)
    if coverage_pct >= 0.95:
        score += 35
        feedback_parts.append("All unique mesh vertices successfully extracted")
    elif coverage_pct >= 0.5:
        score += 15
        feedback_parts.append(f"Partial vertex extraction ({matched_gt}/{len(GROUND_TRUTH_VERTS)})")
    else:
        feedback_parts.append("Extracted points do not geometrically match the DXF mesh")

    # Criteria 3: Duplicate Cleanup (Did they filter the 12 raw corners down to 6 unique nodes?)
    if point_count == len(GROUND_TRUTH_VERTS):
        score += 20
        feedback_parts.append("Duplicate cleanup successful (exactly 6 unique points)")
    elif point_count >= 12:
        feedback_parts.append(f"Deduplication failed: Exported {point_count} overlapping points")
    else:
        score += 10
        feedback_parts.append(f"Partial deduplication: Exported {point_count} points")

    # Criteria 4: VLM Trajectory Verification (Ensure TopoCal UI was used)
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = """You are verifying a CAD task in TopoCal. 
        Did the user interact with the TopoCal software interface to import a DXF or manipulate points?
        Respond in strict JSON: {"used_topocal_ui": true/false}"""
        
        vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_response and vlm_response.get("parsed", {}).get("used_topocal_ui", False):
            score += 30
            feedback_parts.append("VLM verified TopoCal UI interaction")
        else:
            feedback_parts.append("VLM could not confirm TopoCal was used (Possible bypass)")
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")

    # Threshold calculation (requires file creation, geometry match, and either VLM or Dedup success)
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }