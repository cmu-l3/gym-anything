#!/usr/bin/env python3
"""
Verifier for export_sagittal_image_series task.

Scoring Criteria:
1. Output directory created (10 pts)
2. Contains PNG files (10 pts)
3. File count check (50 pts):
   - Axial export (default) would be ~108 files.
   - Sagittal export (required) would be ~512 files.
   - Pass if count > 200.
4. Aspect Ratio check (30 pts):
   - Axial slices are usually square (1:1).
   - Sagittal slices are rectangular (512x108 -> ~4.7 ratio).
   - Pass if aspect ratio is NOT ~1.0.

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_sagittal_series(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy unavailable"}

    score = 0
    feedback_parts = []
    
    # Load results
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/export_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}

    # 1. Check directory (10 pts)
    if result.get("dir_exists", False):
        score += 10
        feedback_parts.append("Output directory exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Output directory not found"}

    # 2. Check content type (10 pts)
    valid_count = result.get("valid_png_count", 0)
    if valid_count > 0:
        score += 10
        feedback_parts.append(f"Found {valid_count} valid PNG files")
    else:
        feedback_parts.append("No valid PNG files found")

    # 3. Check File Count - CRITICAL for Orientation (50 pts)
    # Native axial is 108 slices. Sagittal is 512 slices.
    file_count = result.get("file_count", 0)
    if file_count > 200:
        score += 50
        feedback_parts.append(f"File count ({file_count}) indicates Sagittal/Coronal re-slicing")
    elif file_count > 80:
        # Likely just standard axial export
        feedback_parts.append(f"File count ({file_count}) suggests default Axial export (Expected > 200)")
    else:
        feedback_parts.append(f"File count too low ({file_count})")

    # 4. Check Aspect Ratio (30 pts)
    # Axial 512x512 = 1.0. Sagittal 512x108 != 1.0.
    is_square = result.get("is_square", True)
    aspect = result.get("avg_aspect_ratio", 1.0)
    
    if not is_square and file_count > 0:
        score += 30
        feedback_parts.append(f"Aspect ratio ({aspect:.2f}) confirms non-axial view")
    elif file_count > 0:
        feedback_parts.append(f"Aspect ratio ({aspect:.2f}) suggests square (Axial) slices")

    # 5. Anti-gaming check (Pass/Fail gate)
    new_files = result.get("files_created_during_task", 0)
    if new_files == 0 and file_count > 0:
        score = 0
        feedback_parts = ["Files exist but were not created during this task session"]

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }