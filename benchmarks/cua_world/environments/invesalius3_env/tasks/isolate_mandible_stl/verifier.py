#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_isolate_mandible_stl(traj, env_info, task_info):
    """
    Verify that the mandible was successfully isolated and exported.
    
    Criteria:
    1. File exists and was created during the task.
    2. Valid STL format.
    3. Z-axis span < 120mm (Ensures it's not the full skull, which is ~200mm).
    4. Volume between 20,000 and 200,000 mm^3 (Mandible volume range).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    max_z_span = metadata.get('max_z_span_mm', 120.0)
    min_vol = metadata.get('min_volume_mm3', 20000.0)
    max_vol = metadata.get('max_volume_mm3', 200000.0)
    min_triangles = metadata.get('min_triangle_count', 1000)

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    file_exists = result.get('file_exists', False)
    created_fresh = result.get('created_during_task', False)
    analysis = result.get('stl_analysis', {})
    
    # Criterion 1: File Existence & Creation (20 pts)
    if file_exists and created_fresh:
        score += 20
        feedback.append("File created successfully.")
    elif file_exists:
        score += 10
        feedback.append("File exists but timestamp is old (reused?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # Criterion 2: Valid STL (10 pts)
    if analysis.get('valid_stl', False) and analysis.get('triangle_count', 0) > min_triangles:
        score += 10
        feedback.append(f"Valid STL with {analysis['triangle_count']} triangles.")
    else:
        return {"passed": False, "score": score, "feedback": "Invalid STL or empty mesh."}

    # Criterion 3: Z-Height Check (35 pts)
    # The mandible is short. If the Z-span is large, they likely exported the whole skull.
    z_span = analysis.get('z_span', 999.0)
    if z_span < max_z_span:
        score += 35
        feedback.append(f"Z-axis span {z_span:.1f}mm is within mandible range (<{max_z_span}mm).")
    else:
        feedback.append(f"Z-axis span {z_span:.1f}mm is too large (likely full skull).")

    # Criterion 4: Volume Check (35 pts)
    # Mandible has a specific volume range.
    vol = analysis.get('volume_mm3', 0.0)
    if min_vol <= vol <= max_vol:
        score += 35
        feedback.append(f"Volume {vol:.0f} mm3 is realistic for a mandible.")
    else:
        if vol < min_vol:
            feedback.append(f"Volume {vol:.0f} mm3 is too small (incomplete or noise).")
        else:
            feedback.append(f"Volume {vol:.0f} mm3 is too large (likely includes other bones).")

    passed = score >= 80  # Needs 80 to pass (must get most geometry checks right)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": analysis
    }