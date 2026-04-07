#!/usr/bin/env python3
import json
import os
import math
import logging
import tempfile

logger = logging.getLogger(__name__)

def verify_ntm_dredging_zone_setup(traj, env_info, task_info):
    """
    Verify the NTM Dredging Zone Setup task.
    
    Checks:
    1. Scenario files exist.
    2. Exactly 5 objects created in othership.ini.
    3. Objects are stationary (Speed=0).
    4. Coordinates match the NTM (converted to DD, West is negative).
    5. Correct distinct models used (Buoys vs Dredger).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load ground truth from metadata
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    gt_corners = ground_truth.get('corners', [])
    gt_center = ground_truth.get('center', {})
    tolerance = ground_truth.get('tolerance', 0.002)

    # 1. Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Criterion 1: Scenario Existence (10 pts) ---
    if result.get('scenario_exists'):
        score += 10
        feedback.append("Scenario files created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Scenario files not found."}

    # --- Criterion 2: Object Count (15 pts) ---
    objects = result.get('objects', [])
    obj_count = len(objects)
    
    if obj_count == 5:
        score += 15
        feedback.append("Correct number of objects (5).")
    else:
        feedback.append(f"Incorrect number of objects: found {obj_count}, expected 5.")
        if obj_count == 0:
             return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # --- Criterion 3: Speed Configuration (15 pts) ---
    # All objects must be stationary (speed 0)
    speeds_correct = True
    for obj in objects:
        try:
            speed = float(obj.get('InitialSpeed', -1))
            if speed > 0.1: # Allow slight float error but basically 0
                speeds_correct = False
                feedback.append(f"Object at {obj.get('InitialLat')} has non-zero speed: {speed}.")
        except:
            speeds_correct = False
            
    if speeds_correct:
        score += 15
        feedback.append("All objects are stationary.")
    else:
        feedback.append("Some objects have incorrect speed (must be 0).")

    # --- Criterion 4: Coordinate Accuracy (50 pts total) ---
    # We need to match the 5 found objects to the 5 ground truth points (4 corners + 1 center)
    # Strategy: For each ground truth point, find the closest object.
    
    gt_points = gt_corners + [gt_center]
    matched_objects = set()
    matches_found = 0
    coordinate_score = 0
    
    # Points per correct match = 50 / 5 = 10 pts
    
    for pt in gt_points:
        target_lat = pt['lat']
        target_long = pt['long']
        label = pt.get('label', 'Unknown')
        
        best_dist = float('inf')
        best_obj_idx = -1
        
        for idx, obj in enumerate(objects):
            try:
                # Handle potential parsing errors
                lat = float(obj.get('InitialLat', 999))
                lng = float(obj.get('InitialLong', 999))
                
                # Euclidean distance is fine for small distances
                dist = math.sqrt((lat - target_lat)**2 + (lng - target_long)**2)
                
                if dist < best_dist:
                    best_dist = dist
                    best_obj_idx = idx
            except:
                continue
                
        if best_dist <= tolerance:
            matches_found += 1
            coordinate_score += 10
            matched_objects.add(best_obj_idx)
            feedback.append(f"Matched {label} correctly.")
        else:
            # Check for common error: Missing negative sign on longitude
            flipped_dist = float('inf')
            try:
                if best_obj_idx != -1:
                    f_lat = float(objects[best_obj_idx].get('InitialLat', 999))
                    f_lng = float(objects[best_obj_idx].get('InitialLong', 999))
                    flipped_dist = math.sqrt((f_lat - target_lat)**2 + ((-f_lng) - target_long)**2)
            except:
                pass
                
            if flipped_dist <= tolerance:
                feedback.append(f"Failed {label}: Longitude sign incorrect (West must be negative).")
            else:
                feedback.append(f"Failed {label}: No object found within tolerance (Closest dist: {best_dist:.4f}).")

    score += coordinate_score

    # --- Criterion 5: Model Selection (10 pts) ---
    # Check if center object looks like a ship and corners look like buoys
    # We identify the center match based on coordinates
    
    center_lat = gt_center['lat']
    center_long = gt_center['long']
    
    model_score = 0
    center_found = False
    
    for obj in objects:
        try:
            lat = float(obj.get('InitialLat', 999))
            lng = float(obj.get('InitialLong', 999))
            dist = math.sqrt((lat - center_lat)**2 + (lng - center_long)**2)
            
            if dist <= tolerance:
                # This is the center object
                obj_type = obj.get('Type', '').lower()
                if any(x in obj_type for x in ['ship', 'vessel', 'tanker', 'dredg', 'coaster']):
                    model_score += 5
                    feedback.append("Center object uses appropriate vessel model.")
                elif 'buoy' in obj_type:
                    feedback.append("Center object is a buoy, expected a vessel/dredger.")
                else:
                    feedback.append(f"Center object type '{obj_type}' is ambiguous.")
                center_found = True
                break
        except:
            continue
            
    # Check at least one other object is a buoy
    buoy_found = False
    for obj in objects:
        obj_type = obj.get('Type', '').lower()
        if 'buoy' in obj_type or 'mark' in obj_type:
            buoy_found = True
            break
            
    if buoy_found:
        model_score += 5
        feedback.append("Buoy models detected.")
    
    score += model_score

    # Final result
    passed = (score >= 75)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }