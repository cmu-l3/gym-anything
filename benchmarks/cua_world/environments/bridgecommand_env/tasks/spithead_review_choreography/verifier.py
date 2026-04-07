#!/usr/bin/env python3
import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spithead_review(traj, env_info, task_info):
    """
    Verify the Spithead Fleet Review scenario.
    
    Metrics:
    1. Geodetic Geometry (Fleet Line): Ships must be at correct bearing and spacing.
    2. Ownship Positioning: Correct offset from the line.
    3. Timing Schedule: Physics-based check of the text file.
    """
    
    # 1. Load result using copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    fleet = data.get('fleet', [])
    ownship = data.get('ownship', {})
    schedule_lines = data.get('schedule_content', [])
    scenario_created = data.get('files_created_during_task', {}).get('scenario', False)

    if not scenario_created or not fleet:
        return {"passed": False, "score": 0, "feedback": "Scenario files not created or empty."}

    # 3. Math Helpers (Spherical approximation is sufficient for small scale)
    def to_coords(lat_str, long_str):
        try:
            return float(lat_str), float(long_str)
        except (ValueError, TypeError):
            return None, None

    def haversine_nm(lat1, lon1, lat2, lon2):
        R = 3440.065 # Earth radius in NM
        phi1, phi2 = math.radians(lat1), math.radians(lat2)
        dphi = math.radians(lat2 - lat1)
        dlambda = math.radians(lon2 - lon1)
        a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
        return R * c

    def bearing_deg(lat1, lon1, lat2, lon2):
        phi1, phi2 = math.radians(lat1), math.radians(lat2)
        dlambda = math.radians(lon2 - lon1)
        y = math.sin(dlambda) * math.cos(phi2)
        x = math.cos(phi1)*math.sin(phi2) - math.sin(phi1)*math.cos(phi2)*math.cos(dlambda)
        theta = math.atan2(y, x)
        return (math.degrees(theta) + 360) % 360

    # Task Parameters
    START_LAT = 50.741667 # 50° 44.50' N
    START_LON = -1.133333 # 001° 08.00' W
    TARGET_BEARING = 115.0
    TARGET_SPACING = 0.4
    OWNSHIP_OFFSET = 0.2
    
    score = 0
    feedback = []

    # --- CHECK 1: FLEET GEOMETRY (40 pts) ---
    # Sort fleet by index just in case
    # Note: Export script already sorted them by index key
    
    if len(fleet) != 5:
        feedback.append(f"Incorrect number of ships: {len(fleet)} (expected 5)")
    else:
        score += 5
        
        # Check Ship 1 Position
        s1 = fleet[0]
        lat1, lon1 = to_coords(s1.get('initlat', s1.get('lat')), s1.get('initlong', s1.get('long')))
        
        if lat1 is not None:
            dist_start = haversine_nm(START_LAT, START_LON, lat1, lon1)
            if dist_start < 0.05:
                score += 5
                feedback.append("Ship 1 anchored correctly.")
            else:
                feedback.append(f"Ship 1 start pos error: {dist_start:.3f} nm")
        
        # Check Linearity and Spacing
        spacing_errors = []
        bearing_errors = []
        
        prev_lat, prev_lon = lat1, lon1
        
        valid_chain = True
        for i in range(1, 5):
            curr = fleet[i]
            clat, clon = to_coords(curr.get('initlat', curr.get('lat')), curr.get('initlong', curr.get('long')))
            
            if prev_lat is None or clat is None:
                valid_chain = False
                break
                
            dist = haversine_nm(prev_lat, prev_lon, clat, clon)
            brg = bearing_deg(prev_lat, prev_lon, clat, clon)
            
            spacing_errors.append(abs(dist - TARGET_SPACING))
            # Bearing difference handling wrapping
            b_diff = abs(brg - TARGET_BEARING)
            if b_diff > 180: b_diff = 360 - b_diff
            bearing_errors.append(b_diff)
            
            prev_lat, prev_lon = clat, clon

        if valid_chain:
            avg_space_err = sum(spacing_errors)/len(spacing_errors)
            avg_brg_err = sum(bearing_errors)/len(bearing_errors)
            
            if avg_space_err < 0.05: 
                score += 15
                feedback.append(f"Spacing correct (avg err {avg_space_err:.3f} nm)")
            else:
                feedback.append(f"Spacing incorrect (avg err {avg_space_err:.3f} nm)")
                
            if avg_brg_err < 2.0:
                score += 15
                feedback.append(f"Line bearing correct (avg err {avg_brg_err:.1f}°)")
            else:
                feedback.append(f"Line bearing incorrect (avg err {avg_brg_err:.1f}°)")

    # --- CHECK 2: OWNSHIP POSITIONING (30 pts) ---
    olat, olon = to_coords(ownship.get('initiallat', 0), ownship.get('initiallong', 0))
    ohead = float(ownship.get('initialbearing', 0))
    
    if olat is not None:
        # Check heading
        if abs(ohead - 115) < 5:
            score += 5
        else:
            feedback.append(f"Ownship heading {ohead}° incorrect")

        # Check Offset (Cross Track Error)
        # We define the fleet line from Ship 1 (lat1, lon1) to Ship 5.
        # But simply: Calculate bearing/dist from Ship 1 to Ownship.
        # Ideally, Ownship is 0.5nm BEHIND Ship 1, and 0.2nm RIGHT.
        # 115° is track. Reverse is 295°. Right is 205°.
        # So Ownship relative to Ship 1 should be roughly:
        # 0.5nm at 295° (to get behind) PLUS 0.2nm at 205° (to get right/south).
        # Vector addition roughly.
        
        # Simpler method: Calculate XTE relative to the infinite line passing through Ship 1 at 115°.
        if fleet and lat1 is not None:
            brg_to_own = bearing_deg(lat1, lon1, olat, olon)
            dist_to_own = haversine_nm(lat1, lon1, olat, olon)
            
            # Angle relative to track
            rel_angle = math.radians(brg_to_own - TARGET_BEARING)
            xte = math.sin(rel_angle) * dist_to_own # Positive is Right/Starboard
            ate = math.cos(rel_angle) * dist_to_own # Along track distance
            
            # Target: XTE = +0.2 (South/Right), ATE = -0.5 (Behind)
            
            if abs(xte - 0.2) < 0.05:
                score += 15
                feedback.append("Ownship lateral offset correct (0.2nm South/Stbd)")
            else:
                feedback.append(f"Ownship lateral offset incorrect (XTE: {xte:.2f} nm)")
                
            if abs(ate - (-0.5)) < 0.1: # Tolerant on start distance
                score += 10
                feedback.append("Ownship longitudinal start correct (-0.5nm)")
            else:
                feedback.append(f"Ownship start distance incorrect ({ate:.2f} nm)")

    # --- CHECK 3: SCHEDULE (30 pts) ---
    # Expected: 10 kts. Spacing 0.4 nm.
    # Time between ships = 0.4 / 10 = 0.04 hrs = 2.4 mins = 2m 24s.
    # Expected: T+0:00, T+2:24, T+4:48, T+7:12, T+9:36
    
    schedule_text = " ".join(schedule_lines)
    
    # Very basic check for the timestamps
    timestamps = ["0:00", "2:24", "4:48", "7:12", "9:36"]
    found_timestamps = 0
    for ts in timestamps:
        if ts in schedule_text:
            found_timestamps += 1
    
    # Check for minutes logic if exact strings missing
    import re
    times = re.findall(r'(\d+):(\d+)', schedule_text)
    
    if found_timestamps >= 3:
        score += 30
        feedback.append("Schedule timestamps match physics.")
    elif len(times) >= 5:
        # Check intervals of parsed times
        intervals_correct = True
        try:
            secs = [int(m)*60 + int(s) for m, s in times]
            # check differences
            diffs = [secs[i+1]-secs[i] for i in range(len(secs)-1)]
            avg_diff = sum(diffs)/len(diffs)
            # Expected 144 seconds
            if abs(avg_diff - 144) < 10:
                score += 20 # Partial credit for correct intervals but maybe wrong start
                feedback.append("Schedule intervals correct.")
            else:
                feedback.append(f"Schedule intervals incorrect (avg {avg_diff}s vs 144s)")
        except:
            pass
    else:
        feedback.append("Schedule file content could not be parsed or incorrect.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }