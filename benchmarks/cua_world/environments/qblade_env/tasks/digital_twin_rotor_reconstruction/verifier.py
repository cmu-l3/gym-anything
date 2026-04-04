#!/usr/bin/env python3
"""
Verifier for Digital Twin Rotor Reconstruction.
"""

import json
import os
import math
import tempfile
import logging
from typing import List, Dict, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def parse_qblade_dat(content: str) -> List[Tuple[float, float]]:
    """
    Parses QBlade graph export format.
    Usually:
    Header lines...
    x_val y_val
    x_val y_val
    ...
    """
    data_points = []
    lines = content.splitlines()
    for line in lines:
        line = line.strip()
        if not line:
            continue
        # Skip header lines that don't start with numbers
        if not (line[0].isdigit() or line[0] == '-'):
            continue
            
        parts = line.split()
        if len(parts) >= 2:
            try:
                x = float(parts[0])
                y = float(parts[1])
                data_points.append((x, y))
            except ValueError:
                continue
    return data_points

def interpolate_value(data: List[Tuple[float, float]], target_x: float) -> Optional[float]:
    """
    Linear interpolation to find y at target_x.
    Assumes data is sorted by x.
    """
    if not data:
        return None
    
    # Sort just in case
    data.sort(key=lambda p: p[0])
    
    # Exact match or bounds check
    for i, (x, y) in enumerate(data):
        if math.isclose(x, target_x, abs_tol=1e-5):
            return y
        if x > target_x:
            if i == 0:
                return y # Closest point (extrapolation/boundary)
            
            # Interpolate
            x_prev, y_prev = data[i-1]
            slope = (y - y_prev) / (x - x_prev)
            return y_prev + slope * (target_x - x_prev)
            
    return data[-1][1] # Fallback to last point

def verify_digital_twin(traj, env_info, task_info):
    """
    Verifies that the rotor geometry matches the datasheet specifications.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', [])
    tolerances = metadata.get('tolerances', {'chord': 0.05, 'twist': 0.15})

    # Files to retrieve
    files_to_check = {
        'result_json': '/tmp/task_result.json',
        'chord_dat': '/home/ga/Documents/projects/chord_dist.dat',
        'twist_dat': '/home/ga/Documents/projects/twist_dist.dat',
        'project_wpa': '/home/ga/Documents/projects/legacy_v1_reconstruction.wpa'
    }

    local_files = {}
    
    # Create temp dir for retrieval
    with tempfile.TemporaryDirectory() as temp_dir:
        for name, remote_path in files_to_check.items():
            local_path = os.path.join(temp_dir, name)
            try:
                copy_from_env(remote_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    local_files[name] = local_path
            except Exception as e:
                logger.warning(f"Failed to copy {name}: {e}")

        # Load Result JSON
        if 'result_json' not in local_files:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task status"}
        
        with open(local_files['result_json'], 'r') as f:
            task_status = json.load(f)

        score = 0
        feedback = []

        # Criterion 1: Project File Saved (10 pts)
        if task_status.get('project_file', {}).get('exists') and \
           task_status.get('project_file', {}).get('created_during_task'):
            score += 10
            feedback.append("Project file saved.")
        else:
            feedback.append("Project file missing or not saved during task.")

        # Criterion 2: Airfoil Generation Evidence (10 pts)
        # We rely on log evidence or implicit evidence (if geometry is correct, airfoils must exist)
        # We'll give partial points for logs, full verification comes from data
        if task_status.get('logs_mention_4424') or task_status.get('logs_mention_4412'):
            score += 10
            feedback.append("Log evidence of airfoil generation found.")
        else:
            feedback.append("No explicit log evidence of airfoil generation (checking geometry).")

        # Criterion 3: Chord Distribution Accuracy (40 pts)
        chord_score = 0
        chord_errors = []
        if 'chord_dat' in local_files:
            try:
                with open(local_files['chord_dat'], 'r') as f:
                    chord_data = parse_qblade_dat(f.read())
                
                if not chord_data:
                    feedback.append("Chord export file empty or invalid.")
                else:
                    valid_points = 0
                    for station in ground_truth:
                        target_pos = station['pos']
                        target_chord = station['chord']
                        
                        actual_chord = interpolate_value(chord_data, target_pos)
                        
                        if actual_chord is not None:
                            error = abs(actual_chord - target_chord)
                            if error <= tolerances['chord']:
                                valid_points += 1
                            else:
                                chord_errors.append(f"Pos {target_pos}m: Expected {target_chord}, Got {actual_chord:.2f}")
                        else:
                            chord_errors.append(f"Pos {target_pos}m: No data")
                    
                    # Score calculation
                    if valid_points == len(ground_truth):
                        chord_score = 40
                        feedback.append("Chord distribution matches datasheet perfectly.")
                    elif valid_points > 0:
                        chord_score = int(40 * (valid_points / len(ground_truth)))
                        feedback.append(f"Chord distribution partially correct ({valid_points}/{len(ground_truth)} points).")
                    else:
                        feedback.append("Chord distribution values incorrect.")
            except Exception as e:
                feedback.append(f"Error analyzing chord data: {str(e)}")
        else:
            feedback.append("Chord data file not exported.")
        
        score += chord_score

        # Criterion 4: Twist Distribution Accuracy (40 pts)
        twist_score = 0
        twist_errors = []
        if 'twist_dat' in local_files:
            try:
                with open(local_files['twist_dat'], 'r') as f:
                    twist_data = parse_qblade_dat(f.read())
                
                if not twist_data:
                    feedback.append("Twist export file empty or invalid.")
                else:
                    valid_points = 0
                    for station in ground_truth:
                        target_pos = station['pos']
                        target_twist = station['twist']
                        
                        actual_twist = interpolate_value(twist_data, target_pos)
                        
                        if actual_twist is not None:
                            error = abs(actual_twist - target_twist)
                            if error <= tolerances['twist']:
                                valid_points += 1
                            else:
                                twist_errors.append(f"Pos {target_pos}m: Expected {target_twist}, Got {actual_twist:.2f}")
                        else:
                            twist_errors.append(f"Pos {target_pos}m: No data")
                    
                    if valid_points == len(ground_truth):
                        twist_score = 40
                        feedback.append("Twist distribution matches datasheet perfectly.")
                    elif valid_points > 0:
                        twist_score = int(40 * (valid_points / len(ground_truth)))
                        feedback.append(f"Twist distribution partially correct ({valid_points}/{len(ground_truth)} points).")
                    else:
                        feedback.append("Twist distribution values incorrect.")
            except Exception as e:
                feedback.append(f"Error analyzing twist data: {str(e)}")
        else:
            feedback.append("Twist data file not exported.")

        score += twist_score

        # Deduct for specific errors if detailed feedback requested
        if chord_errors:
            feedback.append(f"Chord mismatch details: {'; '.join(chord_errors[:2])}...")
        if twist_errors:
            feedback.append(f"Twist mismatch details: {'; '.join(twist_errors[:2])}...")

        return {
            "passed": score >= 70,
            "score": score,
            "feedback": " ".join(feedback)
        }