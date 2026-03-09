#!/usr/bin/env python3
"""
Verifier for design_troposkein_rotor task.

Task requires:
1. Creating a VAWT blade with Troposkein geometry (variable radius).
2. Height ~40m, Radius ~20m.
3. Using NACA 0018 airfoil.
4. Saving as .wpa project.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_troposkein_rotor(traj, env_info, task_info):
    """
    Verify the Troposkein rotor design project.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    target_height = metadata.get('target_height', 40.0)
    target_radius = metadata.get('target_radius', 20.0)
    tolerance = metadata.get('tolerance_percent', 5.0) / 100.0

    # 1. Get JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check basic file existence
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Project file 'troposkein_rotor.wpa' not found."}

    # 2. Get the actual project file for content analysis
    project_file_path = "/home/ga/Documents/projects/troposkein_rotor.wpa"
    temp_wpa = tempfile.NamedTemporaryFile(delete=False, suffix='.wpa')
    try:
        copy_from_env(project_file_path, temp_wpa.name)
        with open(temp_wpa.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve project file: {e}"}
    finally:
        if os.path.exists(temp_wpa.name):
            os.unlink(temp_wpa.name)

    score = 0
    feedback_parts = []
    
    # === Scoring Criteria ===

    # Criterion 1: File Exists & Created During Task (20 pts)
    if task_result.get('file_created_during_task', False):
        score += 20
        feedback_parts.append("Project saved correctly")
    else:
        # If it exists but wasn't created now (unlikely given setup script deletes it), partial credit
        score += 10
        feedback_parts.append("Project file exists (timestamp issue)")

    # Criterion 2: Airfoil Check (10 pts)
    # Check for NACA 0018 reference in content
    if re.search(r"NACA.*0018", content, re.IGNORECASE):
        score += 10
        feedback_parts.append("NACA 0018 airfoil used")
    else:
        feedback_parts.append("NACA 0018 airfoil not found in project")

    # Criterion 3: Geometry Analysis (Troposkein Shape) (40 pts)
    # Parse blade definition. QBlade wpa files usually store blade tables.
    # We look for numeric data that looks like a blade table with varying radius.
    # We expect multiple lines of data.
    
    # Approximate parsing strategy:
    # Find numeric sequences. A Troposkein blade will have:
    # - Start pos (0) -> Radius ~0
    # - Mid pos (~20) -> Radius ~20
    # - End pos (~40) -> Radius ~0
    
    # Let's extract all floating point numbers
    # QBlade WPA format varies, but usually clear text. 
    # We'll look for the characteristic "Max Radius" and "Total Height" indirectly
    # by parsing all numbers and looking for the distribution.
    
    numbers = [float(x) for x in re.findall(r'-?\d+\.\d+', content)]
    
    if len(numbers) > 50: # valid project usually has many numbers
        # Try to find the blade geometry section.
        # It usually follows "VAWT_BLADE" or similar tag, but generic check is safer for robustness.
        
        # Check if we have numbers near target_radius (20.0)
        has_max_radius = any(abs(n - target_radius) < (target_radius * tolerance) for n in numbers)
        
        # Check if we have numbers near target_height (40.0) or height/2 (20.0)
        # Note: Some definitions use half-height, some full.
        has_height_dim = any(abs(n - target_height) < (target_height * tolerance) for n in numbers)
        
        # KEY CHECK: Variable radius. 
        # A straight blade has constant radius. A Troposkein has varying radius.
        # We look for a sequence of Radius values. 
        # If the project contains many distinct values in the 0-20 range, it's likely curved.
        radius_values = [n for n in numbers if 0.1 < n <= (target_radius * 1.1)]
        distinct_radii = len(set([round(r, 1) for r in radius_values]))
        
        if distinct_radii > 5:
            score += 40
            feedback_parts.append("Blade geometry shows variable radius (Troposkein shape)")
        elif distinct_radii > 0:
            # Maybe a straight blade?
            feedback_parts.append("Blade geometry appears to be straight/constant radius (not Troposkein)")
        else:
            feedback_parts.append("Could not determine blade geometry")
            
        # Dimension checks
        if has_max_radius:
            score += 10
            feedback_parts.append(f"Max radius matches target (~{target_radius}m)")
        
        if has_height_dim:
            score += 10
            feedback_parts.append(f"Height matches target (~{target_height}m)")
            
    else:
        feedback_parts.append("Project file content seems empty or invalid")

    # Criterion 4: Element Count (>10) (10 pts)
    # The 'distinct_radii > 5' check implicitly covers this, but we can double check file size/complexity
    if task_result.get('output_size_bytes', 0) > 2000:
        score += 10
        feedback_parts.append("Project complexity sufficient")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }