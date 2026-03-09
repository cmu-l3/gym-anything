#!/usr/bin/env python3
"""
Verifier for generate_hurricane_track_line task.
Verifies that the agent created a sorted polyline track from shuffled CSV points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hurricane_track(traj, env_info, task_info):
    """
    Verify the hurricane track generation.
    
    Criteria:
    1. Output Shapefile exists and was created during task.
    2. Geometry is Polyline (Type 3).
    3. Feature Count >= 1 (should be 1 continuous line or few segments).
    4. Bounding Box matches Hurricane Katrina approximate area.
    5. Path Length is within valid range (Crucial Anti-Gaming Check).
       - Sorted points (Correct): ~28-32 degrees total length.
       - Unsorted points (Wrong): > 100 degrees total length (zig-zagging).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Extract data
    analysis = result.get("analysis", {})
    file_created = result.get("file_created_during_task", False)
    
    exists = analysis.get("exists", False)
    shape_type = analysis.get("shape_type", 0)
    bbox = analysis.get("bbox", [0,0,0,0])
    total_length = analysis.get("total_length", 0.0)
    feature_count = analysis.get("feature_count", 0)
    
    score = 0
    feedback_parts = []
    
    # 1. File Existence & Creation (20 pts)
    if exists and file_created:
        score += 20
        feedback_parts.append("Output file created")
    elif exists:
        score += 10
        feedback_parts.append("Output file exists (but timestamp ambiguous)")
    else:
        return {"passed": False, "score": 0, "feedback": "Output shapefile not found"}
        
    # 2. Geometry Type (20 pts)
    # 3 = Polyline, 23 = PolylineZ
    if shape_type in [3, 23]:
        score += 20
        feedback_parts.append("Geometry is Polyline")
    else:
        feedback_parts.append(f"Wrong geometry type: {shape_type} (Expected Polyline/3)")
        
    # 3. Valid Bounding Box (20 pts)
    # Katrina: Lon ~ -90 to -75, Lat ~ 23 to 35
    # BBox: [xmin, ymin, xmax, ymax]
    if (bbox[0] > -95 and bbox[0] < -70 and 
        bbox[2] > -95 and bbox[2] < -70 and
        bbox[1] > 20 and bbox[1] < 40 and 
        bbox[3] > 20 and bbox[3] < 40):
        score += 20
        feedback_parts.append("Bounding box valid")
    else:
        feedback_parts.append(f"Bounding box mismatch: {bbox}")
        
    # 4. Sorting / Path Validity (40 pts)
    # The raw unsorted points create a massive zig-zag if connected in file order.
    # The sorted points create a smooth path.
    # Euclidean length check:
    # Sorted ~ 30.0 units
    # Unsorted > 60.0 units
    
    # Tolerance
    MAX_VALID_LENGTH = 50.0 
    MIN_VALID_LENGTH = 10.0 # Just to ensure it's not a single point
    
    if total_length > MIN_VALID_LENGTH and total_length < MAX_VALID_LENGTH:
        score += 40
        feedback_parts.append(f"Path sorted correctly (Length: {total_length:.2f})")
    else:
        feedback_parts.append(f"Path appears unsorted or invalid (Length: {total_length:.2f}). Did you use the SEQ field?")
        
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }