#!/usr/bin/env python3
"""
Verifier for vessel_nav_light_setup task.
Checks if boat.ini contains [Light] sections matching the randomized geometry spec.
"""

import json
import os
import configparser
import logging
import math
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vessel_nav_light_setup(traj, env_info, task_info):
    """
    Verify the navigation light configuration.
    
    Rubric (100 pts):
    - File validity (10 pts): boat.ini is valid INI
    - File modification (10 pts): File was actually edited
    - Masthead Light (20 pts): Correct color & ~pos
    - Port Light (20 pts): Correct color & ~pos (Y < 0)
    - Starboard Light (20 pts): Correct color & ~pos (Y > 0)
    - Stern Light (10 pts): Correct color & ~pos
    - Precision (10 pts): All coordinates within tight tolerance (0.1m)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # Setup temporary paths
    temp_dir = tempfile.mkdtemp()
    submitted_ini_path = os.path.join(temp_dir, "boat_submitted.ini")
    truth_path = os.path.join(temp_dir, "ground_truth.json")
    result_json_path = os.path.join(temp_dir, "task_result.json")

    try:
        # Copy files from container
        copy_from_env("/tmp/boat_submitted.ini", submitted_ini_path)
        copy_from_env("/tmp/ground_truth.json", truth_path)
        copy_from_env("/tmp/task_result.json", result_json_path)
        
        # Load Ground Truth
        with open(truth_path, 'r') as f:
            ground_truth = json.load(f)
            
        # Load Task Metadata
        with open(result_json_path, 'r') as f:
            task_result = json.load(f)
            
        # check if file modified
        if task_result.get("file_modified", False):
            score += 10
        else:
            feedback.append("Warning: boat.ini was not modified timestamp-wise.")

        # Parse INI
        config = configparser.ConfigParser(strict=False)
        # Bridge Command INI files often have duplicate sections (multiple [Light]), 
        # which standard ConfigParser doesn't handle well by default.
        # We need to manually parse or use a list-based parsing approach.
        
        # Manual parsing to handle multiple [Light] sections
        lights = []
        with open(submitted_ini_path, 'r') as f:
            current_section = None
            current_light = {}
            for line in f:
                line = line.strip()
                if line.startswith('[') and line.endswith(']'):
                    if current_section == 'Light' and current_light:
                        lights.append(current_light)
                    current_section = line[1:-1]
                    current_light = {}
                elif current_section == 'Light' and '=' in line:
                    key, val = line.split('=', 1)
                    current_light[key.strip().lower()] = val.strip()
            # Capture last section
            if current_section == 'Light' and current_light:
                lights.append(current_light)
        
        if not lights:
            return {"passed": False, "score": score, "feedback": "No [Light] sections found in boat.ini"}
        
        score += 10 # Valid parse with lights found
        
        # Helper to find light by color/position
        def match_light(target_name, target_data):
            # Target data from ground truth
            t_x, t_y, t_z = target_data['x'], target_data['y'], target_data['z']
            t_color = target_data['color'] # 'red', 'green', 'white'
            
            best_match = None
            min_dist = 999.0
            
            for light in lights:
                try:
                    # Get color from INI
                    r = int(light.get('red', 0))
                    g = int(light.get('green', 0))
                    b = int(light.get('blue', 0))
                    
                    # Determine color category
                    l_color = 'unknown'
                    if r > 200 and g > 200 and b > 200: l_color = 'white'
                    elif r > 200 and g < 100: l_color = 'red'
                    elif g > 200 and r < 100: l_color = 'green'
                    
                    if l_color != t_color:
                        continue
                        
                    # Calculate distance
                    x = float(light.get('x', 0))
                    y = float(light.get('y', 0))
                    z = float(light.get('z', 0))
                    
                    dist = math.sqrt((x - t_x)**2 + (y - t_y)**2 + (z - t_z)**2)
                    
                    # Special check for port/stbd distinction (Y sign)
                    if target_name == 'port' and y >= 0: continue # Port must be negative Y
                    if target_name == 'starboard' and y <= 0: continue # Stbd must be positive Y
                    if target_name == 'masthead' and z < 4: continue # Masthead should be high
                    
                    if dist < min_dist:
                        min_dist = dist
                        best_match = light
                        
                except ValueError:
                    continue
            
            return best_match, min_dist

        # Check each required light
        precision_bonus = True
        
        # 1. Masthead
        mh, mh_dist = match_light('masthead', ground_truth['lights']['masthead'])
        if mh:
            if mh_dist < 1.0:
                score += 20
                feedback.append(f"Masthead light found (error {mh_dist:.2f}m)")
            else:
                score += 10
                feedback.append(f"Masthead light color correct but position off (error {mh_dist:.2f}m)")
                precision_bonus = False
        else:
            feedback.append("Masthead light missing or wrong color")
            precision_bonus = False

        # 2. Port
        pt, pt_dist = match_light('port', ground_truth['lights']['port'])
        if pt:
            if pt_dist < 1.0:
                score += 20
                feedback.append(f"Port light found (error {pt_dist:.2f}m)")
            else:
                score += 10
                feedback.append(f"Port light color correct but position off (error {pt_dist:.2f}m)")
                precision_bonus = False
        else:
            feedback.append("Port light missing, wrong color, or wrong side")
            precision_bonus = False

        # 3. Starboard
        sb, sb_dist = match_light('starboard', ground_truth['lights']['starboard'])
        if sb:
            if sb_dist < 1.0:
                score += 20
                feedback.append(f"Starboard light found (error {sb_dist:.2f}m)")
            else:
                score += 10
                feedback.append(f"Starboard light color correct but position off (error {sb_dist:.2f}m)")
                precision_bonus = False
        else:
            feedback.append("Starboard light missing, wrong color, or wrong side")
            precision_bonus = False
            
        # 4. Stern
        st, st_dist = match_light('stern', ground_truth['lights']['stern'])
        if st:
            if st_dist < 1.0:
                score += 10
                feedback.append(f"Stern light found (error {st_dist:.2f}m)")
            else:
                score += 5
                feedback.append(f"Stern light color correct but position off (error {st_dist:.2f}m)")
                precision_bonus = False
        else:
            feedback.append("Stern light missing or wrong color")
            precision_bonus = False

        # Precision Bonus (0.1m tolerance)
        if precision_bonus:
            if mh_dist < 0.2 and pt_dist < 0.2 and sb_dist < 0.2 and st_dist < 0.2:
                score += 10
                feedback.append("High precision coordinates achieved!")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }