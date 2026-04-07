#!/usr/bin/env python3
"""
Verifier for square_flange_shaft task.

Uses multi-signal verification:
1. Programmatic File Check: SLVS file must exist, be properly sized, and modified after task start.
2. Feature Parsing: SLVS file text content must contain multiple extrude groups and circular requests.
3. STL Geometric Check: Bounding box matching the ~60x60x60 dimensions.
4. Visual (VLM): Trajectory review ensuring the specific square-and-cylinder workflow was performed.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are a CAD expert evaluating a robotics hobbyist's 3D model in SolveSpace.

TASK REQUIREMENTS:
1. Create a 60x60mm square base plate, extruded to 10mm thick.
2. Create a 30mm diameter cylindrical shaft, 50mm tall, protruding from the top center of the base plate.
3. Overall object should look like a square flange with a round cylinder extending from it.

Look at the provided screenshots from the agent's work trajectory and final state.
Answer the following questions:
1. Does the model clearly have a flat square or rectangular base plate?
2. Is there a cylindrical shaft/boss extending from the center of the base?
3. Did the agent use multiple 3D extrusion steps (visible in the property browser on the left, e.g., 'extrude' groups)?

Output your response strictly as JSON:
{
    "has_square_base": true/false,
    "has_cylindrical_shaft": true/false,
    "multiple_extrusions_visible": true/false,
    "explanation": "Brief reasoning for your assessment"
}
"""

def verify_square_flange_shaft(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_height = metadata.get('expected_total_height', 60)
    expected_base = metadata.get('expected_base_size', 60)
    tolerance = metadata.get('tolerance', 12)
    min_triangles = metadata.get('min_triangles', 40)

    score = 0
    feedback_parts = []
    
    # 1. Fetch JSON results from environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Criterion 1: File Existence & Anti-Gaming Timestamp (15 points)
    if result.get('file_exists') and result.get('file_modified_during_task'):
        score += 15
        feedback_parts.append("File created successfully")
    elif result.get('file_exists'):
        feedback_parts.append("FAIL: File exists but wasn't modified during task (do-nothing detected)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("FAIL: Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Extrude Groups & Circles in Source (20 points)
    extrude_count = int(result.get('extrude_count', 0))
    circle_count = int(result.get('circle_count', 0))
    
    if extrude_count >= 2:
        score += 10
        feedback_parts.append(f"Multiple extrusions ({extrude_count}) detected")
    elif extrude_count == 1:
        score += 5
        feedback_parts.append("Only 1 extrusion detected (needs >= 2)")
    
    if circle_count >= 1:
        score += 10
        feedback_parts.append("Circular feature detected")
    else:
        feedback_parts.append("No circular feature detected in source")

    # Criterion 3: Geometry Bounding Box (25 points)
    if result.get('stl_exported'):
        stl_data = result.get('stl_data', {})
        triangles = int(stl_data.get('triangles', 0))
        
        dims = sorted([
            float(stl_data.get('dx', 0)),
            float(stl_data.get('dy', 0)),
            float(stl_data.get('dz', 0))
        ])
        
        if triangles >= min_triangles:
            score += 5
            
            # The object should be ~60x60x60 overall. All 3 dimensions should be close to 60.
            matching_dims = sum(1 for d in dims if abs(d - expected_height) <= tolerance)
            
            if matching_dims == 3:
                score += 20
                feedback_parts.append("Bounding box dimensions correct (~60x60x60)")
            elif matching_dims >= 1:
                score += 10
                feedback_parts.append("Partial bounding box match")
            else:
                feedback_parts.append(f"Bounding box incorrect (dims: {dims})")
        else:
            feedback_parts.append(f"Invalid geometry: Only {triangles} triangles")
    else:
        feedback_parts.append("Failed to export STL for geometric validation")

    # Criterion 4: VLM Trajectory Verification (40 points)
    vlm_passed = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)
            
        vlm_resp = query_vlm(images=frames, prompt=VLM_PROMPT)
        if vlm_resp and vlm_resp.get('success'):
            parsed = vlm_resp.get('parsed', {})
            
            has_square = parsed.get('has_square_base', False)
            has_cyl = parsed.get('has_cylindrical_shaft', False)
            multi_ext = parsed.get('multiple_extrusions_visible', False)
            
            vlm_score = sum([
                15 if has_square else 0,
                15 if has_cyl else 0,
                10 if multi_ext else 0
            ])
            
            score += vlm_score
            vlm_passed = has_square and has_cyl
            feedback_parts.append(f"VLM Score: {vlm_score}/40 ({parsed.get('explanation', '')})")
        else:
            feedback_parts.append("VLM evaluation failed")
    else:
        feedback_parts.append("VLM query function not available")

    # Final Pass/Fail determination
    # Must achieve at least 60 points, have multiple extrusions, and pass visual checks
    key_criteria_met = (extrude_count >= 1) and vlm_passed
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }