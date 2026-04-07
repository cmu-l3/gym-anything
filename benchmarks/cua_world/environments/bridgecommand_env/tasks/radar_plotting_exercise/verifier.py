#!/usr/bin/env python3
import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def to_float(val, default=0.0):
    try:
        return float(val)
    except (ValueError, TypeError):
        return default

def calculate_rhumb_line(lat1, lon1, lat2, lon2):
    """Calculate range (nm) and bearing (deg) between two points."""
    # Approximate flat earth for Solent (short distances)
    # 1 deg lat = 60 nm
    # 1 deg lon = 60 * cos(lat) nm
    
    mean_lat = (lat1 + lat2) / 2.0
    mean_lat_rad = math.radians(mean_lat)
    
    d_lat_nm = (lat2 - lat1) * 60.0
    d_lon_nm = (lon2 - lon1) * 60.0 * math.cos(mean_lat_rad)
    
    dist = math.sqrt(d_lat_nm**2 + d_lon_nm**2)
    
    angle = math.degrees(math.atan2(d_lon_nm, d_lat_nm))
    bearing = (angle + 360) % 360
    
    return dist, bearing

def calculate_cpa_tcpa(r, b_deg, v_own, c_own, v_tgt, c_tgt):
    """
    Calculate CPA (nm) and TCPA (min).
    r: range (nm)
    b_deg: true bearing (deg)
    v: speed (kts)
    c: course (deg)
    """
    # Convert to radians
    b = math.radians(b_deg)
    co = math.radians(c_own)
    ct = math.radians(c_tgt)
    
    # Position vectors (Target relative to Ownship)
    # x = East, y = North
    px = r * math.sin(b)
    py = r * math.cos(b)
    
    # Velocity vectors
    vox = v_own * math.sin(co)
    voy = v_own * math.cos(co)
    
    vtx = v_tgt * math.sin(ct)
    vty = v_tgt * math.cos(ct)
    
    # Relative velocity vector (Target - Own)
    rvx = vtx - vox
    rvy = vty - voy
    
    v_rel = math.sqrt(rvx**2 + rvy**2)
    
    if v_rel < 0.1:
        return 0.0, 0.0 # No relative motion
    
    # Time to CPA (hours) = -(P . V_rel) / |V_rel|^2
    # P . V_rel = px*rvx + py*rvy
    t_cpa_hours = -(px * rvx + py * rvy) / (v_rel**2)
    
    # CPA distance
    # Pos at CPA = P + V_rel * t_cpa
    cpa_x = px + rvx * t_cpa_hours
    cpa_y = py + rvy * t_cpa_hours
    cpa_dist = math.sqrt(cpa_x**2 + cpa_y**2)
    
    return cpa_dist, t_cpa_hours * 60.0 # Return TCPA in minutes

def verify_radar_plotting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    md = task_info.get('metadata', {})
    
    # Load result
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
    
    data = result.get("parsed_data", {})
    files = data.get("files", {})
    solution_text = data.get("solution_content", "").lower()
    
    score = 0
    feedback = []
    
    # === CRITERION 1: Scenario Structure & Environment (25 pts) ===
    if data.get("scenario_found"):
        score += 5
        feedback.append("Scenario directory created.")
    else:
        feedback.append("Scenario directory NOT found.")
    
    env = files.get("environment", {})
    
    # Time (Night: 22-04 or 1-4)
    # StartTime is usually hours.decimal
    st = to_float(env.get("StartTime", -1))
    if (0 <= st <= 4) or (22 <= st <= 24):
        score += 5
        feedback.append(f"Nighttime setting correct ({st}h).")
    else:
        feedback.append(f"Time not nighttime (found {st}).")
        
    # Visibility (2.0 - 4.0)
    vis = to_float(env.get("VisibilityRange", 0))
    if 2.0 <= vis <= 4.0:
        score += 5
        feedback.append("Visibility correct.")
    elif 1.0 <= vis <= 5.0:
        score += 2 # Partial
        feedback.append("Visibility acceptable.")
    else:
        feedback.append(f"Visibility out of range ({vis}).")

    # Solent check
    setting = env.get("Setting", "").lower()
    if "solent" in setting:
        score += 5
    else:
        feedback.append("Environment setting not Solent.")
        
    # Weather check
    wx = to_float(env.get("Weather", 99))
    if wx <= 1.5:
        score += 5
        feedback.append("Weather calm.")
        
    # === CRITERION 2: Ownship Configuration (10 pts) ===
    own = files.get("ownship", {})
    own_lat = to_float(own.get("InitialLat", 0))
    own_lon = to_float(own.get("InitialLong", 0))
    own_hdg = to_float(own.get("InitialBearing", -1))
    own_spd = to_float(own.get("InitialSpeed", 0))
    
    # Target: 50.8, -1.15
    if abs(own_lat - 50.8) < 0.02 and abs(own_lon - (-1.15)) < 0.02:
        score += 5
        feedback.append("Ownship position correct.")
    else:
        feedback.append(f"Ownship position incorrect ({own_lat}, {own_lon}).")
        
    if abs(own_hdg - 270) < 10 and abs(own_spd - 12) < 2:
        score += 5
        feedback.append("Ownship heading/speed correct.")
    
    # === CRITERION 3: Traffic Configuration (20 pts) ===
    others = files.get("othership", {})
    num_vessels = to_float(others.get("Number", 0))
    
    if num_vessels == 4:
        score += 5
        feedback.append("Correct number of traffic vessels (4).")
    else:
        feedback.append(f"Incorrect number of vessels ({num_vessels}).")
    
    # Analyze vessels to see if they match encounter types
    # We parse the 'othership' dict which has keys like "Type(0)", "InitLat(0)", etc.
    # We'll reconstruct vessel objects
    vessels = []
    for i in range(int(num_vessels)):
        v = {
            "lat": to_float(others.get(f"InitLat({i})", 0)),
            "lon": to_float(others.get(f"InitLong({i})", 0)),
            "course": to_float(others.get(f"Bearing({i},0)", 0)), # Assumes leg 0 bearing defines initial course
            "speed": to_float(others.get(f"Speed({i},0)", 0))
        }
        vessels.append(v)
        
    # Check for specific encounter types (loose check based on relative position/course)
    encounters_found = 0
    # Head-on: West of us, heading East (approx)
    if any(v['lon'] < -1.20 and 70 < v['course'] < 110 for v in vessels): encounters_found += 1
    # Overtaking: East of us, heading West (faster than 12)
    if any(v['lon'] > -1.13 and 250 < v['course'] < 290 and v['speed'] > 14 for v in vessels): encounters_found += 1
    
    if encounters_found >= 2:
        score += 15
        feedback.append("Key encounter types identified in scenario.")
    elif encounters_found > 0:
        score += 8
        feedback.append("Some encounter types identified.")
        
    # === CRITERION 4: Radar Settings (15 pts) ===
    conf = files.get("config", {})
    arpa = to_float(conf.get("arpa_on", 0))
    full = to_float(conf.get("full_radar", 0))
    rng = to_float(conf.get("max_radar_range", 0))
    
    if arpa == 1: score += 5
    if full == 1: score += 5
    if rng >= 48: score += 5
    
    # === CRITERION 5: Solution Worksheet Accuracy (30 pts) ===
    # This is the critical math check. We calculate truth based on the scenario files 
    # the agent created, then grep the solution file for those numbers.
    
    math_score = 0
    math_hits = 0
    
    if not solution_text:
        feedback.append("Solution worksheet missing or empty.")
    else:
        # For each vessel in the scenario, calculate truth
        for i, v in enumerate(vessels):
            # Calculate Range/Bearing
            r_truth, b_truth = calculate_rhumb_line(own_lat, own_lon, v['lat'], v['lon'])
            
            # Calculate CPA/TCPA
            cpa_truth, tcpa_truth = calculate_cpa_tcpa(
                r_truth, b_truth, own_spd, own_hdg, v['speed'], v['course']
            )
            
            # Check if these numbers appear in the text (with tolerance)
            # We search for the integer part or 1 decimal place
            
            # Range check (±0.5)
            r_str = f"{r_truth:.1f}"
            if r_str in solution_text or f"{int(r_truth)}" in solution_text:
                math_hits += 1
                
            # CPA check (±0.5)
            cpa_str = f"{cpa_truth:.1f}"
            if cpa_str in solution_text or f"{int(cpa_truth)}" in solution_text:
                math_hits += 1
                
            # TCPA check (±2 min)
            tcpa_str = f"{tcpa_truth:.0f}"
            if tcpa_str in solution_text:
                math_hits += 1
                
        # We expect roughly 3 hits per vessel (Range, CPA, TCPA) * 4 vessels = 12 hits max
        # Scale score: 6+ hits = full points (allow for formatting diffs)
        if math_hits >= 6:
            math_score = 30
            feedback.append(f"Solution calculations match scenario geometry ({math_hits} matches).")
        elif math_hits >= 3:
            math_score = 15
            feedback.append(f"Some solution calculations match ({math_hits} matches).")
        else:
            feedback.append(f"Solution calculations do not match scenario (Truth: R={r_truth:.1f}, CPA={cpa_truth:.1f}).")
            
    score += math_score
    
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }