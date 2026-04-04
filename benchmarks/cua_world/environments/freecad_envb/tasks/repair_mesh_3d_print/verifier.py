#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_repair_mesh_3d_print(traj, env_info, task_info):
    """
    Verifies that the agent repaired the mesh and scaled it correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    target_scale = metadata.get('target_scale_factor', 1.02)
    scale_tolerance = metadata.get('scale_tolerance', 0.005)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    mesh_data = result.get("mesh_analysis", {})
    timestamp_data = result.get("timestamp_check", {})
    
    output_exists = mesh_data.get("output_exists", False)
    is_solid = mesh_data.get("is_solid", False)
    scale_ratio = mesh_data.get("scale_ratio", 0.0)
    file_created_during_task = timestamp_data.get("file_created_during_task", False)

    score = 0
    feedback_parts = []
    passed = False

    # Criterion 1: File Existence (10 pts)
    if output_exists:
        score += 10
        feedback_parts.append("Output file exists")
    else:
        feedback_parts.append("Output file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Anti-gaming Timestamp (10 pts)
    if file_created_during_task:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp is old (pre-task)")

    # Criterion 3: Mesh Validity (Repair) (40 pts)
    if is_solid:
        score += 40
        feedback_parts.append("Mesh is watertight (Repaired)")
    else:
        feedback_parts.append("Mesh is NOT watertight (Still has holes)")

    # Criterion 4: Scaling (40 pts)
    # Check if scale ratio is within tolerance of 1.02
    diff = abs(scale_ratio - target_scale)
    if diff <= scale_tolerance:
        score += 40
        feedback_parts.append(f"Scale correct (Ratio: {scale_ratio:.4f})")
    elif diff <= 0.01: # Partial credit for being close
        score += 20
        feedback_parts.append(f"Scale slightly off (Ratio: {scale_ratio:.4f}, Target: {target_scale})")
    else:
        feedback_parts.append(f"Scale incorrect (Ratio: {scale_ratio:.4f}, Target: {target_scale})")

    # Pass logic
    if score >= 90:
        passed = True
    elif score >= 60 and is_solid:
        # Pass if at least solid and file exists, even if scale is slightly off
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }