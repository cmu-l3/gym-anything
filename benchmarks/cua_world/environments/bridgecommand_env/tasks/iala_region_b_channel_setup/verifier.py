#!/usr/bin/env python3
import json
import os
import math
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_iala_region_b_channel_setup(traj, env_info, task_info):
    """
    Verifies the IALA Region B Channel Setup task.
    
    Criteria:
    1. Scenario & Files Exist (10 pts)
    2. Ownship Position (10 pts) - Miami coordinates, Westbound
    3. Buoy Count (20 pts) - Exactly 6 buoys
    4. Channel Geometry (20 pts) - 3 pairs/gates at correct longitudes
    5. IALA B Compliance (40 pts) - North=Red, South=Green
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Scenario Existence (10 pts) ---
    if result.get("scenario_exists") and result.get("files_exist"):
        score += 10
        feedback.append("Scenario directory and INI files found.")
    else:
        feedback.append("Scenario directory or required INI files missing.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # --- Criterion 2: Ownship Configuration (10 pts) ---
    try:
        own_lat = float(result['ownship']['lat'])
        own_long = float(result['ownship']['long'])
        own_head = float(result['ownship']['heading'])
        
        # Target: 25.766, -80.080
        dist = math.sqrt((own_lat - 25.766)**2 + (own_long + 80.080)**2)
        
        if dist < 0.01: # Within ~1km
            score += 5
            feedback.append("Ownship position correct.")
        else:
            feedback.append(f"Ownship position incorrect ({own_lat}, {own_long}).")

        # Heading 270 (West) +/- 20 deg
        if 250 <= own_head <= 290:
            score += 5
            feedback.append("Ownship heading correct (Westbound).")
        else:
            feedback.append(f"Ownship heading incorrect ({own_head}).")
            
    except (ValueError, TypeError):
        feedback.append("Could not parse ownship data.")

    # --- Criterion 3: Buoy Count (20 pts) ---
    buoys = result.get('buoys', {}).get('items', [])
    buoy_count = len(buoys)
    
    if buoy_count == 6:
        score += 20
        feedback.append("Correct number of buoys (6).")
    else:
        feedback.append(f"Incorrect number of buoys: {buoy_count} (expected 6).")
        # Partial credit
        if buoy_count > 0: score += 5

    # --- Criterion 4 & 5: Geometry and Color (60 pts total) ---
    # We need to group buoys into gates based on Longitude
    # Gate Longitudes: -80.100, -80.110, -80.120
    
    gates = {
        "Gate 1 (-80.100)": [],
        "Gate 2 (-80.110)": [],
        "Gate 3 (-80.120)": []
    }
    
    orphans = []
    
    for b in buoys:
        blong = b.get('long', 0)
        matched = False
        for target_long in [-80.100, -80.110, -80.120]:
            if abs(blong - target_long) < 0.003: # Tolerance for placement
                key = f"Gate {[-80.100, -80.110, -80.120].index(target_long) + 1} ({target_long})"
                # Map generic key to specific dict key
                if target_long == -80.100: k = "Gate 1 (-80.100)"
                elif target_long == -80.110: k = "Gate 2 (-80.110)"
                else: k = "Gate 3 (-80.120)"
                
                gates[k].append(b)
                matched = True
                break
        if not matched:
            orphans.append(b)

    geometry_score = 0
    color_score = 0
    
    # Process each gate
    for gate_name, items in gates.items():
        if len(items) == 2:
            geometry_score += 6.66 # 20 pts / 3 gates
            
            # Identify North and South buoy in this pair
            # Sort by Latitude (North is positive/higher)
            items.sort(key=lambda x: x.get('lat', 0), reverse=True)
            north_buoy = items[0]
            south_buoy = items[1]
            
            # Check separation (sanity check)
            lat_diff = north_buoy.get('lat', 0) - south_buoy.get('lat', 0)
            if lat_diff < 0.0005:
                feedback.append(f"{gate_name}: Buoys too close or not N/S separated.")
                continue

            # IALA B CHECK
            # North (Starboard for Westbound) -> Must be RED
            # South (Port for Westbound) -> Must be GREEN
            
            n_type = north_buoy.get('type', '').lower()
            s_type = south_buoy.get('type', '').lower()
            
            gate_color_pass = True
            
            # Check North
            if "red" in n_type or "cone" in n_type:
                pass 
            else:
                gate_color_pass = False
                feedback.append(f"{gate_name}: North buoy should be Red/Cone (found '{n_type}').")

            # Check South
            if "green" in s_type or "can" in s_type:
                pass
            else:
                gate_color_pass = False
                feedback.append(f"{gate_name}: South buoy should be Green/Can (found '{s_type}').")

            # Anti-Gaming: Check for reversed IALA A (Green North / Red South)
            if ("green" in n_type and "red" in s_type):
                feedback.append(f"{gate_name}: CRITICAL - Configured as IALA A (Europe)! Miami is IALA B.")
                gate_color_pass = False

            if gate_color_pass:
                color_score += 13.33 # 40 pts / 3 gates
        
        elif len(items) > 0:
            feedback.append(f"{gate_name}: Found {len(items)} buoys, expected pair.")
        else:
            feedback.append(f"{gate_name}: Missing.")

    score += round(geometry_score)
    score += round(color_score)

    return {
        "passed": score >= 70,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }