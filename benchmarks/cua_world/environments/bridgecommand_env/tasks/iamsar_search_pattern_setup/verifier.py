#!/usr/bin/env python3
import json
import math
import os
import sys

def verify_iamsar_search_pattern(traj, env_info, task_info):
    """
    Verify the IAMSAR Expanding Square search pattern configuration.
    
    Verification Points:
    1. Scenario files existence (10 pts)
    2. Start Position (Datum) accuracy (10 pts)
    3. Pattern Geometry (Bearings & Distances) (50 pts)
    4. Longitude Convergence handling (15 pts)
    5. Target placement (10 pts)
    6. SAP Document existence (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    import tempfile
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. File Existence (10 pts)
    if result.get('scenario_exists') and result['files']['ownship'] and result['files']['environment'] and result['files']['othership']:
        score += 10
        feedback.append("Scenario files created.")
    else:
        feedback.append("Missing scenario files.")
        return {"passed": False, "score": 0, "feedback": "Critical files missing."}

    # Data Parsing
    own_data = result.get('ownship_data', {})
    legs = result.get('ownship_legs', [])
    
    # 2. Start Position (Datum) (10 pts)
    # Expected: 50° 35.00' N, 001° 20.00' W => 50.5833, -1.3333
    expected_lat = 50.5833
    expected_long = -1.3333
    
    try:
        init_lat = float(own_data.get('initiallat', -999))
        init_long = float(own_data.get('initiallong', -999))
        
        if abs(init_lat - expected_lat) < 0.001 and abs(init_long - expected_long) < 0.001:
            score += 10
            feedback.append("Start position correct.")
        else:
            feedback.append(f"Start pos incorrect. Got {init_lat},{init_long}. Expected {expected_lat},{expected_long}.")
    except:
        feedback.append("Could not parse start position.")

    # 3. Geometry Analysis (50 pts) & 4. Longitude Convergence (15 pts)
    # Reconstruct the path
    path = [(init_lat, init_long)]
    for leg in legs:
        try:
            l_lat = float(leg['lat'])
            l_long = float(leg['long'])
            path.append((l_lat, l_long))
        except:
            pass
            
    if len(path) < 9: # Start + 8 legs
        feedback.append(f"Insufficient legs defined. Found {len(path)-1}, expected 8.")
    else:
        feedback.append(f"Found {len(path)-1} legs.")
        
        # Calculate segments
        geom_score = 0
        long_conv_score = 0
        
        # Expanding square sequence: 
        # Leg 1: 0.5nm N (000)
        # Leg 2: 0.5nm E (090)
        # Leg 3: 1.0nm S (180)
        # Leg 4: 1.0nm W (270)
        # Leg 5: 1.5nm N (000)
        # Leg 6: 1.5nm E (090)
        # Leg 7: 2.0nm S (180)
        # Leg 8: 2.0nm W (270)
        
        expected_dists = [0.5, 0.5, 1.0, 1.0, 1.5, 1.5, 2.0, 2.0]
        expected_bearings = [0, 90, 180, 270, 0, 90, 180, 270]
        
        for i in range(8):
            p1 = path[i]
            p2 = path[i+1]
            
            # Calculate dist/bearing
            # Simple rhumb line approx is sufficient for small distances or Haversine
            d_lat = p2[0] - p1[0]
            d_long = p2[1] - p1[1]
            
            mean_lat_rad = math.radians((p1[0] + p2[0]) / 2.0)
            dep = d_long * math.cos(mean_lat_rad) # Departure (E-W distance in degrees scaled)
            
            # Distance in nm (1 deg lat = 60 nm)
            dist_nm = math.sqrt((d_lat * 60)**2 + (dep * 60)**2)
            
            # Bearing
            angle = math.degrees(math.atan2(dep, d_lat)) # atan2(x, y) -> x=dep (East), y=d_lat (North)
            bearing = (angle + 360) % 360
            
            exp_dist = expected_dists[i]
            exp_brg = expected_bearings[i]
            
            # Check Bearing (Tolerance 10 deg)
            brg_diff = abs(bearing - exp_brg)
            if brg_diff > 180: brg_diff = 360 - brg_diff
            
            leg_ok = True
            if brg_diff < 10:
                geom_score += 3.125 # 25 pts total for bearings / 8
            else:
                feedback.append(f"Leg {i+1} Bearing wrong. Got {bearing:.1f}, expected {exp_brg}.")
                leg_ok = False
                
            # Check Distance (Tolerance 0.1 nm or 10%)
            if abs(dist_nm - exp_dist) < 0.15:
                geom_score += 3.125 # 25 pts total for distances / 8
            else:
                feedback.append(f"Leg {i+1} Distance wrong. Got {dist_nm:.2f}nm, expected {exp_dist}nm.")
                leg_ok = False

            # Check Longitude Convergence (Departure)
            # If the user just added 0.5 to Longitude without cos(lat), d_long would be 0.5/60 = 0.0083
            # But correct d_long should be 0.5/(60*0.635) = 0.0131
            # We check if d_long is closer to the correct value than the raw value
            if exp_brg in [90, 270]: # East/West legs
                raw_dlong = exp_dist / 60.0
                correct_dlong = exp_dist / (60.0 * math.cos(math.radians(p1[0])))
                
                # If they are close to correct dlong
                if abs(abs(d_long) - correct_dlong) < 0.002:
                    long_conv_score += 3.75 # 15 pts total / 4 EW legs
                elif abs(abs(d_long) - raw_dlong) < 0.002:
                    feedback.append(f"Leg {i+1}: Forgot cos(lat) correction.")
                else:
                    pass # Just wrong

        score += geom_score + long_conv_score
        feedback.append(f"Geometry Score: {geom_score:.1f}/50. Conv Score: {long_conv_score:.1f}/15")

    # 5. Target Placement (10 pts)
    # Target should be at end of Leg 8
    othership = result.get('othership_data', {})
    try:
        t_lat = float(othership.get('initiallat(1)', -999))
        t_long = float(othership.get('initiallong(1)', -999))
        
        # Expected end position
        if len(path) >= 9:
            end_lat, end_long = path[8]
            dist_err = math.sqrt(((t_lat - end_lat)*60)**2 + ((t_long - end_long)*60*0.63)**2)
            if dist_err < 0.2:
                score += 10
                feedback.append("Target placed correctly.")
            else:
                feedback.append(f"Target misplaced by {dist_err:.2f}nm.")
    except:
        feedback.append("Could not check target position.")

    # 6. SAP Document (5 pts)
    if result.get('files', {}).get('plan'):
        score += 5
        feedback.append("SAP document exists.")

    return {
        "passed": score >= 70,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }