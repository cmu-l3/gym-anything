#!/usr/bin/env python3
"""
Verifier for scale_and_export_stl task.

Checks:
1. STL file creation and validity (30 pts)
2. QBlade Project file creation (20 pts)
3. Geometric accuracy (Target Radius = 1.0m +/- 0.05m) (40 pts)
4. Application usage (10 pts)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scale_and_export_stl(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_radius = metadata.get('target_radius_m', 1.0)
    tolerance = metadata.get('radius_tolerance_m', 0.05)

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Check STL File (30 pts)
    stl_exists = result.get('stl_exists', False)
    stl_size = result.get('stl_size', 0)
    stl_fresh = result.get('stl_created_during_task', False)
    
    if stl_exists and stl_fresh and stl_size > 1024: # > 1KB
        score += 30
        feedback_parts.append("Valid STL file exported")
    elif stl_exists:
        score += 15
        feedback_parts.append("STL file exists but may be empty or old")
    else:
        feedback_parts.append("STL file not found")

    # 3. Check Project File (20 pts)
    wpa_exists = result.get('wpa_exists', False)
    wpa_fresh = result.get('wpa_created_during_task', False)
    wpa_path = result.get('wpa_path', "")
    
    if wpa_exists and wpa_fresh:
        score += 20
        feedback_parts.append("Scaled project saved")
    elif wpa_exists:
        score += 10
        feedback_parts.append("Project file exists but not newly created")
    else:
        feedback_parts.append("Project file not saved")

    # 4. Check Geometry (Radius) (40 pts)
    # We need to copy the WPA file and parse it to find the max radial position
    radius_correct = False
    measured_radius = 0.0
    
    if wpa_exists and wpa_path:
        temp_wpa = tempfile.NamedTemporaryFile(delete=False, suffix='.wpa')
        try:
            copy_from_env(wpa_path, temp_wpa.name)
            
            # Parse WPA (Text-based)
            # Look for lines like "Pos = 1.0" or "Station_X_Pos = 1.0" inside blade definition
            # We'll extract all "Pos" values and find the max.
            positions = []
            with open(temp_wpa.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                # Regex for QBlade WPA station position format
                # Common formats: "Pos = 12.5" or "Station_1_Pos = 0.5"
                # We'll look for numeric assignments to keys ending in "Pos"
                matches = re.findall(r'(?:Pos|Position)\s*=\s*([-+]?[0-9]*\.?[0-9]+)', content, re.IGNORECASE)
                for m in matches:
                    try:
                        positions.append(float(m))
                    except ValueError:
                        continue
            
            if positions:
                measured_radius = max(positions)
                if abs(measured_radius - target_radius) <= tolerance:
                    score += 40
                    radius_correct = True
                    feedback_parts.append(f"Blade radius correct ({measured_radius:.3f}m)")
                else:
                    feedback_parts.append(f"Blade radius incorrect (Found {measured_radius:.3f}m, expected {target_radius}m)")
            else:
                feedback_parts.append("Could not parse blade geometry from project file")
                
        except Exception as e:
            feedback_parts.append(f"Failed to analyze project geometry: {e}")
        finally:
            if os.path.exists(temp_wpa.name):
                os.unlink(temp_wpa.name)
    else:
        feedback_parts.append("Skipping geometry check (no project file)")

    # 5. App Running (10 pts)
    if result.get('app_was_running', False):
        score += 10
        feedback_parts.append("QBlade was running")
    else:
        feedback_parts.append("QBlade was not running")

    # Final Pass Determination
    # Must have STL, Project, and Correct Radius
    passed = (stl_exists and wpa_exists and radius_correct)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }