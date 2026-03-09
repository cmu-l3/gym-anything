#!/usr/bin/env python3
"""
Verifier for simplify_country_geometries task.

Verifies:
1. Output shapefile exists and was created during the task.
2. Feature count is preserved (no countries lost).
3. Vertex count is significantly reduced (simplification actually happened).
4. Output is a valid Polygon layer.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_simplify_country_geometries(traj, env_info, task_info):
    """
    Verify that the shapefile was simplified correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get verification parameters
    metadata = task_info.get('metadata', {})
    expected_reduction = metadata.get('expected_reduction_min_percent', 10)  # Conservative 10%

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    analysis = result.get('analysis', {})
    app_running = result.get('app_was_running', False)
    
    score = 0
    feedback_parts = []
    passed = False

    # 1. Output Existence (20 pts)
    if analysis.get('output_exists'):
        score += 10
        if analysis.get('output_created_during_task'):
            score += 10
            feedback_parts.append("New output file created")
        else:
            feedback_parts.append("Output file exists but was not created during this session")
    else:
        feedback_parts.append("Output shapefile not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Feature Count Preservation (20 pts)
    input_count = analysis.get('input_features', 0)
    output_count = analysis.get('output_features', 0)
    
    if output_count > 0:
        if abs(input_count - output_count) == 0:
            score += 20
            feedback_parts.append(f"Feature count preserved ({output_count})")
        elif abs(input_count - output_count) < 5:
            score += 10
            feedback_parts.append(f"Feature count slightly different ({output_count} vs {input_count})")
        else:
            feedback_parts.append(f"Feature count mismatch ({output_count} vs {input_count})")
    else:
        feedback_parts.append("Output contains zero features")

    # 3. Vertex Reduction (40 pts)
    reduction = analysis.get('reduction_percent', 0)
    input_verts = analysis.get('input_vertices', 0)
    output_verts = analysis.get('output_vertices', 0)

    if reduction > expected_reduction:
        score += 40
        feedback_parts.append(f"Vertices significantly reduced (-{reduction:.1f}%)")
    elif reduction > 0:
        score += 20
        feedback_parts.append(f"Vertices slightly reduced (-{reduction:.1f}%)")
    elif input_verts > 0 and output_verts >= input_verts:
        feedback_parts.append("No vertex reduction detected (did simplification run?)")
    
    # 4. Geometry Validity (10 pts)
    if analysis.get('geometry_type_match') and analysis.get('valid_geometry'):
        score += 10
        feedback_parts.append("Geometry type correct (Polygon)")

    # 5. App State (10 pts)
    if app_running:
        score += 10
        feedback_parts.append("gvSIG was running")

    # Determine Pass/Fail
    # Requirements: File created, Features approx preserved, Reduction achieved
    key_requirements = (
        analysis.get('output_created_during_task') and
        analysis.get('output_features', 0) > 0 and
        reduction >= 1.0  # At least 1% reduction
    )
    
    if score >= 60 and key_requirements:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "input_vertices": input_verts,
            "output_vertices": output_verts,
            "reduction_percent": reduction
        }
    }