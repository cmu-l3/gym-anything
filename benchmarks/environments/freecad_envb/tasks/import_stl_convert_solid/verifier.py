#!/usr/bin/env python3
"""
Verifier for import_stl_convert_solid task.

Criteria:
1. Output file exists and was created during task.
2. STL import occurred (Mesh object or derived solid exists).
3. A valid Solid shape exists in the document.
4. The Solid is closed (watertight).
5. The Solid volume matches the ground truth (within tolerance).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_stl_convert_solid(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    volume_tolerance = metadata.get('volume_tolerance', 0.15) # 15% tolerance

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Output file exists (10 pts)
    if result.get("output_exists", False):
        score += 10
        feedback_parts.append("Output file created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # 2. Timestamp check (5 pts)
    if result.get("file_created_during_task", False):
        score += 5
    else:
        feedback_parts.append("Warning: File timestamp incorrect (anti-gaming).")

    # 3. STL Import evidence (10 pts)
    if result.get("stl_imported", False):
        score += 10
        feedback_parts.append("STL import confirmed.")
    else:
        feedback_parts.append("No evidence of STL import.")

    # 4. Solid Shape exists (25 pts)
    if result.get("has_solid", False):
        score += 25
        feedback_parts.append("Solid shape found.")
    else:
        feedback_parts.append("No solid shape found in document.")

    # 5. Solid Validity (15 pts)
    if result.get("solid_valid", False):
        score += 15
        feedback_parts.append("Solid is geometrically valid.")
    else:
        feedback_parts.append("Solid geometry is invalid.")

    # 6. Solid Closed (10 pts)
    if result.get("solid_closed", False):
        score += 10
        feedback_parts.append("Solid is watertight (closed).")
    else:
        feedback_parts.append("Solid is not closed (holes detected).")

    # 7. Volume Check (20 pts)
    actual_vol = float(result.get("actual_volume", 0))
    expected_vol = float(result.get("expected_volume", 0))
    
    if expected_vol > 0:
        ratio = actual_vol / expected_vol
        if (1.0 - volume_tolerance) <= ratio <= (1.0 + volume_tolerance):
            score += 20
            feedback_parts.append(f"Volume match ({actual_vol:.0f} vs {expected_vol:.0f}).")
        else:
            feedback_parts.append(f"Volume mismatch ({actual_vol:.0f} vs {expected_vol:.0f}).")
    else:
        # If expected volume missing, fallback to partial points if solid exists
        if result.get("has_solid", False):
            score += 10
            feedback_parts.append("Volume check skipped (ground truth missing).")

    # 8. Conversion Check (5 pts)
    if result.get("has_part_feature", False):
        score += 5
        feedback_parts.append("Conversion workflow detected.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }