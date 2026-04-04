#!/usr/bin/env python3
"""
Verifier for neighboring_high_rise_shading task.

Checks:
1. Simulation ran during session.
2. "NewCondo" FIXED-SHADE object exists.
3. Vertices match expected coordinates within tolerance.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected coordinates
EXPECTED_V1 = (-60, -80, 0)
EXPECTED_V2 = (-60, 80, 0)
EXPECTED_V3 = (-60, 80, 140)
EXPECTED_V4 = (-60, -80, 140)
TOLERANCE = 1.0

def verify_neighboring_high_rise_shading(traj, env_info, task_info):
    """
    Verify the creation of the shading object and simulation run.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Path inside the Windows VM
        copy_from_env("C:\\Users\\Docker\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Simulation (20 pts)
    if result.get('sim_run', False):
        score += 20
        feedback_parts.append("Simulation ran successfully (+20)")
    else:
        feedback_parts.append("Simulation did not run during session")

    # 2. Check Object Existence (20 pts)
    if result.get('object_found', False):
        score += 20
        feedback_parts.append("Object 'NewCondo' created (+20)")
    else:
        feedback_parts.append("Object 'NewCondo' NOT found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Check Vertices (15 pts each)
    vertices = result.get('vertices', {})
    
    def check_vertex(v_data, expected, label):
        if not v_data or v_data.get('x') is None:
            return 0, f"{label} missing"
            
        x, y, z = v_data['x'], v_data['y'], v_data['z']
        ex, ey, ez = expected
        
        # Calculate distance or check individual axes
        if (abs(x - ex) <= TOLERANCE and 
            abs(y - ey) <= TOLERANCE and 
            abs(z - ez) <= TOLERANCE):
            return 15, f"{label} correct"
        else:
            return 0, f"{label} incorrect ({x},{y},{z})"

    s1, f1 = check_vertex(vertices.get('v1'), EXPECTED_V1, "Vertex 1")
    s2, f2 = check_vertex(vertices.get('v2'), EXPECTED_V2, "Vertex 2")
    s3, f3 = check_vertex(vertices.get('v3'), EXPECTED_V3, "Vertex 3")
    s4, f4 = check_vertex(vertices.get('v4'), EXPECTED_V4, "Vertex 4")

    score += (s1 + s2 + s3 + s4)
    feedback_parts.extend([f1, f2, f3, f4])

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }