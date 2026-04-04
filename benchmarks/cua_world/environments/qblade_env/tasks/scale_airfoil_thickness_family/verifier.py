#!/usr/bin/env python3
"""
Verifier for scale_airfoil_thickness_family task.
Checks if airfoils were exported and if they have the correct geometric thickness.
"""

import json
import tempfile
import os
import math
import logging
import sys

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def calculate_max_thickness(coordinates):
    """
    Calculates max thickness-to-chord ratio from a list of (x, y) coordinates.
    Assumes standard airfoil format (Selig or Lednicer), roughly 0..1 in x.
    """
    if not coordinates:
        return 0.0

    # Separate into upper and lower surfaces
    # Simple heuristic: Split points by X axis progression
    # Or simpler: For every X, find min Y and max Y.
    # However, points might not be aligned on X.
    
    # Robust approach:
    # 1. Sort points by X
    # 2. Resample upper and lower surfaces to a common X grid
    # 3. Compute difference
    
    # 1. Identify Upper vs Lower
    # Typical dat file: Trailing Edge -> Upper -> Leading Edge -> Lower -> Trailing Edge
    # Or: Upper (LE->TE) then Lower (LE->TE)
    
    # Let's just separate into two buckets: Y >= 0 (Upper) and Y < 0 (Lower)
    # This assumes non-cambered or lightly cambered aligned with X-axis. 
    # NACA 4415 has camber, so Y could be positive on pressure side near LE.
    
    # Better approach: Geometry parsing
    points = sorted(coordinates, key=lambda p: p[0]) # Sort by X
    
    # Group points by proximity in X (binning)
    bins = {}
    bin_width = 0.01 # 1% chord
    
    for x, y in points:
        b = int(x / bin_width)
        if b not in bins:
            bins[b] = []
        bins[b].append(y)
        
    max_t = 0.0
    
    # Iterate bins (exclude very LE and TE where numerical noise might dominate)
    for b, ys in bins.items():
        x_center = b * bin_width
        if 0.1 < x_center < 0.9: # Check thickness in the main body
            if len(ys) >= 2:
                # Approximate thickness at this station
                thickness = max(ys) - min(ys)
                if thickness > max_t:
                    max_t = thickness
                    
    return max_t

def parse_dat_file(filepath):
    """Parses an airfoil .dat file into a list of (x,y) tuples."""
    coords = []
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
            
        # Skip header (usually first line, sometimes 2)
        # We look for lines with 2 float numbers
        for line in lines:
            parts = line.strip().split()
            if len(parts) == 2:
                try:
                    x = float(parts[0])
                    y = float(parts[1])
                    # Filter out header numbers like "100.0 100.0" (panel counts)
                    if -0.5 <= x <= 1.5 and -1.0 <= y <= 1.0:
                        coords.append((x, y))
                except ValueError:
                    continue
    except Exception as e:
        logger.error(f"Error parsing {filepath}: {e}")
        return []
    return coords

def verify_airfoil_scaling(traj, env_info, task_info):
    """
    Verifies the airfoil scaling task.
    1. Checks if files exist and were created during task.
    2. Downloads files and calculates max thickness.
    3. Scores based on accuracy.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', {})

    # 1. Load Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    score = 0
    feedback = []
    files_metadata = result.get("files", {})
    project_metadata = result.get("project_file", {})

    # 2. Check Project File (10 pts)
    if project_metadata.get("exists") and project_metadata.get("created_during_task"):
        score += 10
        feedback.append("Project file saved.")
    else:
        feedback.append("Project file missing or not saved during task.")

    # 3. Check Airfoils
    processed_count = 0
    
    for key, target_info in targets.items():
        # base, root, tip
        fname = target_info['filename']
        expected = target_info['expected_thickness']
        tol = target_info['tolerance']
        
        file_res = files_metadata.get(fname, {})
        
        if not file_res.get("exists"):
            feedback.append(f"{fname}: Missing.")
            continue
            
        if not file_res.get("created_during_task"):
            feedback.append(f"{fname}: Pre-existing file (Anti-gaming check failed).")
            continue
            
        # Download the .dat file for analysis
        remote_path = file_res.get("path")
        local_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.dat')
        try:
            copy_from_env(remote_path, local_temp.name)
            
            # Parse and Measure
            coords = parse_dat_file(local_temp.name)
            if len(coords) < 10:
                feedback.append(f"{fname}: Invalid format or empty.")
                continue
                
            actual_thickness = calculate_max_thickness(coords)
            error = abs(actual_thickness - expected)
            
            if error <= tol:
                pts = 30 if key != "base" else 20 # 30 for scaled ones, 20 for base
                score += pts
                feedback.append(f"{fname}: Correct (T={actual_thickness:.3f}, Target={expected}).")
            else:
                # Partial credit for being close?
                if error <= tol * 2:
                    pts = 15 if key != "base" else 10
                    score += pts
                    feedback.append(f"{fname}: Close (T={actual_thickness:.3f}, Target={expected}).")
                else:
                    feedback.append(f"{fname}: Incorrect thickness (T={actual_thickness:.3f}, Target={expected}).")
                    
        except Exception as e:
            feedback.append(f"{fname}: Error processing file: {str(e)}")
        finally:
            if os.path.exists(local_temp.name):
                os.unlink(local_temp.name)

    # 4. Valid Formats Check (10 pts)
    # (Implicitly checked if parse_dat_file succeeded for all 3, but let's give points if all exist)
    if all(files_metadata.get(t['filename'], {}).get("exists") for t in targets.values()):
        score += 10
        feedback.append("All expected files exist.")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }