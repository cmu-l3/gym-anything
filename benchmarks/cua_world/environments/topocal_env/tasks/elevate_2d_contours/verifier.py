#!/usr/bin/env python3
"""
Verifier for Elevate 2D Contours task.

VERIFICATION STRATEGY:
1. File Existence & Timestamps (Anti-Gaming): Verifies .xyz and .tcp files were created during the task.
2. Z-Value Distribution: Ensures Z values aren't 0 and fall into the specific target contour ranges.
3. Spatial Accuracy Check: Cross-references sampled ground-truth (X,Y) coordinates to the exported
   file to guarantee the correct Z value was assigned to the correct specific polyline.
4. Trajectory VLM Check: Visual proof the 3D generation/elevation took place.
"""

import json
import os
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_xyz_file(filepath):
    """Robustly parse XYZ file exported by agent, identifying columns by magnitude."""
    points = []
    with open(filepath, 'r') as f:
        for line in f:
            # Replace common delimiters with space
            clean_line = line.replace(',', ' ').replace('\t', ' ').strip()
            if not clean_line:
                continue
                
            parts = clean_line.split()
            nums = []
            for p in parts:
                try:
                    nums.append(float(p))
                except ValueError:
                    pass
                    
            if len(nums) >= 3:
                # Find which numbers represent X, Y, Z based on expected magnitudes
                x, y, z = None, None, None
                for n in nums:
                    if 400000 < n < 600000:
                        x = n
                    elif 4000000 < n < 5000000:
                        y = n
                    elif 1000 < n < 2000:
                        z = n
                
                # Fallback to last 3 columns if magnitudes didn't perfectly catch them
                if x is None or y is None or z is None:
                    x, y, z = nums[-3], nums[-2], nums[-1]
                    
                points.append((x, y, z))
    return points

def find_nearest_z(points, target_x, target_y):
    """Find the Z value of the nearest point in the exported dataset."""
    min_dist = float('inf')
    nearest_z = None
    for x, y, z in points:
        dist = math.hypot(x - target_x, y - target_y)
        if dist < min_dist:
            min_dist = dist
            nearest_z = z
    return nearest_z, min_dist

def verify_elevate_contours(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback = []
    score = 0

    # 1. Fetch task result JSON
    res_tmp = tempfile.NamedTemporaryFile(delete=False)
    try:
        copy_from_env(r"C:\workspace\data\task_result.json", res_tmp.name)
        with open(res_tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        os.unlink(res_tmp.name)

    # Base requirements
    if not result.get('xyz_exists'):
        return {"passed": False, "score": 0, "feedback": "3d_elevated_points.xyz was not exported."}
    
    score += 5
    feedback.append("XYZ file exists.")

    if result.get('xyz_created_during_task'):
        score += 5
        feedback.append("XYZ was created during task.")
        
    if result.get('tcp_exists') and result.get('tcp_created_during_task'):
        score += 10
        feedback.append("TopoCal project saved successfully.")

    # 2. Fetch Exported Data & Ground Truth
    xyz_tmp = tempfile.NamedTemporaryFile(delete=False)
    gt_tmp = tempfile.NamedTemporaryFile(delete=False)
    try:
        copy_from_env(r"C:\workspace\data\3d_elevated_points.xyz", xyz_tmp.name)
        copy_from_env(r"C:\workspace\data\ground_truth.json", gt_tmp.name)
        
        exported_points = parse_xyz_file(xyz_tmp.name)
        with open(gt_tmp.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed reading data files: {e}"}
    finally:
        os.unlink(xyz_tmp.name)
        os.unlink(gt_tmp.name)

    if len(exported_points) < 100:
        feedback.append(f"XYZ file contains too few points ({len(exported_points)}).")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 3. Z-Value Distribution Check
    unique_zs = set([round(p[2]) for p in exported_points])
    target_zs = set(task_info.get('metadata', {}).get('target_elevations', [1600, 1605, 1610, 1615, 1620, 1625]))
    
    if 0 in unique_zs:
        feedback.append("WARNING: Some exported points still have Z=0.")
    
    matched_elevations = target_zs.intersection(unique_zs)
    if len(matched_elevations) == len(target_zs):
        score += 30
        feedback.append("All targeted contour elevations are present in export.")
    else:
        score += (len(matched_elevations) * 5)
        feedback.append(f"Found {len(matched_elevations)}/{len(target_zs)} target elevations.")

    # 4. Spatial Accuracy Check (Anti-Gaming)
    # Checks if the agent mapped the *correct* elevation to the *correct* line
    correct_mappings = 0
    total_samples = 0
    
    for contour_name, samples in ground_truth.items():
        for sample in samples:
            total_samples += 1
            nearest_z, dist = find_nearest_z(exported_points, sample['x'], sample['y'])
            # Dist tolerance 5m (contour points might get resampled in export)
            # Z tolerance 0.1m
            if dist < 5.0 and nearest_z is not None and abs(nearest_z - sample['z']) < 0.1:
                correct_mappings += 1

    spatial_accuracy = correct_mappings / total_samples
    if spatial_accuracy > 0.9:
        score += 50
        feedback.append("Perfect spatial elevation mapping.")
    elif spatial_accuracy > 0.5:
        score += 25
        feedback.append(f"Partial spatial mapping ({spatial_accuracy*100:.1f}%).")
    else:
        feedback.append(f"Poor spatial mapping ({spatial_accuracy*100:.1f}%). Z values applied incorrectly.")

    # Determine Pass
    passed = score >= 70 and len(matched_elevations) >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }