#!/usr/bin/env python3
"""
Verifier for generate_camera_reference_library task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_camera_reference_library(traj, env_info, task_info):
    """
    Verify that the agent downloaded snapshots for all cameras with correct naming.
    """
    # 1. Setup and load result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # Extract data from result
    task_start = result.get('task_start', 0)
    dir_exists = result.get('dir_exists', False)
    ground_truth_cameras = result.get('ground_truth_cameras', [])
    output_files = result.get('output_files', [])
    image_validity = result.get('image_validity', {})

    score = 0
    feedback = []

    # Criterion 1: Directory Creation (10 pts)
    if dir_exists:
        score += 10
        feedback.append("Directory created successfully (+10)")
    else:
        feedback.append("Output directory not found (0/10)")
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    if not ground_truth_cameras:
        return {"passed": False, "score": 0, "feedback": "System error: No cameras found in ground truth."}

    # Prepare maps for checking
    # Map expected filenames to camera names
    expected_files = {}
    for cam in ground_truth_cameras:
        raw_name = cam.get('name', '')
        # Naming convention: replace spaces with underscores, append .jpg
        expected_name = raw_name.replace(" ", "_") + ".jpg"
        expected_files[expected_name] = raw_name

    # Map actual files for quick lookup
    actual_files_map = {f['name']: f for f in output_files}

    # Criterion 2, 3, 4: Coverage, Naming, Validity (Combined logic)
    # We will score per camera
    total_cameras = len(ground_truth_cameras)
    cameras_correct = 0
    valid_images = 0
    timestamps_correct = 0
    
    # Points allocation per camera
    # Total remaining points = 90. 
    # Let's say: 
    # - 40 pts for coverage (file exists with correct name)
    # - 30 pts for content (it's a valid image)
    # - 20 pts for freshness (timestamp > task_start)
    # Normalized: Each camera contributes (90 / total_cameras) to the score
    
    points_per_camera = 90.0 / total_cameras
    
    details = []

    for filename, real_name in expected_files.items():
        cam_score = 0
        status = []
        
        if filename in actual_files_map:
            file_info = actual_files_map[filename]
            
            # 1. Existence/Naming (Covered by map lookup)
            cam_score += (40.0 / total_cameras)
            status.append("Found")
            
            # 2. Validity
            if image_validity.get(filename, False) and file_info.get('size', 0) > 1000: # > 1KB
                cam_score += (30.0 / total_cameras)
                valid_images += 1
                status.append("Valid Image")
            else:
                status.append("Invalid/Empty File")

            # 3. Timestamp (Anti-gaming)
            if file_info.get('mtime', 0) > task_start:
                cam_score += (20.0 / total_cameras)
                timestamps_correct += 1
                status.append("Fresh")
            else:
                status.append("Stale File")
                
            score += cam_score
            cameras_correct += 1
        else:
            status.append("Missing")
        
        details.append(f"{real_name} -> {filename}: {', '.join(status)}")

    # Final tally
    score = min(100, round(score)) # Cap at 100, round to int

    feedback.append(f"Cameras processed: {cameras_correct}/{total_cameras}")
    feedback.append(f"Valid images: {valid_images}/{total_cameras}")
    feedback.append(f"Fresh files: {timestamps_correct}/{total_cameras}")
    
    if cameras_correct < total_cameras:
        feedback.append("Some cameras were missed or misnamed.")
        
    # Pass threshold
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback),
        "details": details
    }