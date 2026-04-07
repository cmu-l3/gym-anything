#!/usr/bin/env python3
"""
Verifier for Compute Traverse Closure task in TopoCal.

Verification Strategy (Multiple Independent Signals):
1. FILE METADATA: Checks if traverse_results.txt was created during the session.
2. DATA INTEGRITY: Parses the text file output, extracting Easting/Northing coordinate pairs.
3. GEOMETRIC VERIFICATION: Computes distances between the extracted sequential coordinates. 
   If the agent correctly adjusted the traverse, the distances between the final points 
   must closely match the input leg distances (within small adjustment tolerances).
   The start coordinate must strictly remain at (500000.0, 4400000.0).
4. VISUAL TRAJECTORY (VLM): Verifies TopoCal traverse/poligonal module was actually used.
"""

import os
import json
import math
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected horizontal distances from the input data
EXPECTED_DISTANCES = [150.235, 200.456, 175.890, 220.123, 185.678]
START_COORD = (500000.0, 4400000.0)

VLM_PROMPT = """You are verifying an agent using the TopoCal CAD software to compute a traverse (Poligonal).
Look at the trajectory frames provided.
1. Is the TopoCal application visible?
2. Did the agent open the traverse or polygon calculation module (often called 'Poligonal' or 'Itinerario' in Spanish)?
3. Can you see data entry of angles and distances in a table/grid interface?
Respond with JSON:
{
    "topocal_visible": true/false,
    "traverse_module_used": true/false,
    "data_entry_visible": true/false
}
"""

def extract_coordinates(file_content: str):
    """
    Robustly extracts coordinates from text.
    Looks for lines containing pairs of numbers matching the approximate location:
    Eastings around 500xxx, Northings around 4400xxx.
    """
    coords = []
    # Regex looks for (Easting) and (Northing) floats within expected ranges
    # Easting: 499000 to 501000, Northing: 4399000 to 4401000
    pattern = re.compile(r'\b(499\d{3}\.\d+|500\d{3}\.\d+)\b.*?\b(4399\d{3}\.\d+|4400\d{3}\.\d+|4401\d{3}\.\d+)\b')
    
    for line in file_content.split('\\n'):
        matches = pattern.findall(line)
        if matches:
            # Take the first match in the line
            easting = float(matches[0][0])
            northing = float(matches[0][1])
            coords.append((easting, northing))
            
    return coords

def verify_traverse_closure(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read exported results
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. File Verification (Anti-gaming & Basic compliance)
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_content = result.get('file_content', '')
    
    if not output_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file traverse_results.txt was not found."
        }
    
    score += 10
    if file_created:
        score += 10
        feedback_parts.append("File created during session (+10)")
    else:
        feedback_parts.append("Warning: File may have existed previously")

    # 3. Geometric Verification (Robust correctness check)
    coords = extract_coordinates(file_content)
    
    geometric_success = False
    if len(coords) < 5:
        feedback_parts.append(f"Found only {len(coords)} coordinate pairs. Expected at least 5.")
    else:
        # Check starting coordinate strictly
        start_e, start_n = coords[0]
        if abs(start_e - START_COORD[0]) < 0.1 and abs(start_n - START_COORD[1]) < 0.1:
            score += 15
            feedback_parts.append("Start coordinate preserved correctly (+15)")
        else:
            feedback_parts.append(f"Start coordinate altered or wrong: ({start_e}, {start_n})")

        # Check distances between sequential points
        actual_distances = []
        for i in range(5):
            p1 = coords[i]
            # Wrap around for the last segment
            p2 = coords[(i + 1) % 5] if i < 4 else coords[0] 
            dist = math.sqrt((p2[0] - p1[0])**2 + (p2[1] - p1[1])**2)
            actual_distances.append(dist)

        # Compare with expected unadjusted distances (allow ±0.5m for compass rule shift)
        distance_errors = [abs(a - e) for a, e in zip(actual_distances, EXPECTED_DISTANCES)]
        
        if all(err < 0.5 for err in distance_errors):
            score += 35
            geometric_success = True
            feedback_parts.append("Adjusted coordinates form correct geometric polygon (+35)")
        else:
            feedback_parts.append(f"Computed geometry does not match input distances. Max error: {max(distance_errors):.2f}m")

    # 4. VLM Trajectory Verification
    vlm_success = False
    query_vlm = env_info.get('query_vlm')
    if query_vlm and 'sample_trajectory_frames' in env_info:
        frames = env_info['sample_trajectory_frames'](traj, n=4)
        vlm_resp = query_vlm(images=frames, prompt=VLM_PROMPT)
        
        if vlm_resp and vlm_resp.get('success'):
            parsed = vlm_resp.get('parsed', {})
            if parsed.get('traverse_module_used') and parsed.get('data_entry_visible'):
                score += 30
                vlm_success = True
                feedback_parts.append("VLM confirmed traverse UI usage (+30)")
            else:
                feedback_parts.append("VLM did not detect traverse computation UI")
        else:
            feedback_parts.append("VLM query failed")
    else:
        # Fallback if VLM unavailable, grant points if geometric succeeded perfectly
        if geometric_success:
            score += 30
            feedback_parts.append("VLM skipped; granted points via perfect geometric match")

    passed = score >= 70 and geometric_success and output_exists
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }