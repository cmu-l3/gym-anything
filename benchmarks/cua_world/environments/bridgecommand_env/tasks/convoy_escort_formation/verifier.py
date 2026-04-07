#!/usr/bin/env python3
import json
import math
import os
import sys

def calculate_bearing_distance(lat1, lon1, lat2, lon2):
    """
    Calculate True Bearing and Distance (nm) between two coordinates.
    Using simple planar approximation suitable for small distances (<50nm).
    1 deg Lat = 60 nm
    1 deg Lon = 60 * cos(lat) nm
    """
    try:
        lat1, lon1, lat2, lon2 = float(lat1), float(lon1), float(lat2), float(lon2)
        
        # Mean latitude for longitude scaling
        mean_lat_rad = math.radians((lat1 + lat2) / 2.0)
        cos_lat = math.cos(mean_lat_rad)
        
        dy_nm = (lat2 - lat1) * 60.0
        dx_nm = (lon2 - lon1) * 60.0 * cos_lat
        
        dist_nm = math.sqrt(dx_nm**2 + dy_nm**2)
        
        # Bearing
        # atan2(x, y) returns angle from Y axis (North) if (x,y) are (East, North)
        # standardized to 0-360
        angle_rad = math.atan2(dx_nm, dy_nm)
        bearing_deg = math.degrees(angle_rad)
        if bearing_deg < 0:
            bearing_deg += 360.0
            
        return bearing_deg, dist_nm
    except:
        return 0.0, 0.0

def verify_convoy_escort_formation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy not available"}

    # Load result
    import tempfile
    tmp_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", tmp_path)
        with open(tmp_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

    score = 0
    feedback = []

    # Metadata targets
    meta = task_info.get("metadata", {})
    center_lat = meta.get("center_lat", 50.80)
    center_lon = meta.get("center_long", 0.50)
    
    # 1. Scenario Existence (10 pts)
    if data.get("scenario_found") and len(data.get("files_present", [])) >= 3:
        score += 10
        feedback.append("Scenario directory and files created.")
    else:
        feedback.append("Scenario files missing.")

    # 2. Environment (10 pts)
    env = data.get("environment", {})
    try:
        if "English Channel" in env.get("Setting", ""):
            score += 5
        vis = float(env.get("VisibilityRange", 0))
        if vis >= 8.0:
            score += 5
    except:
        pass

    # 3. Ownship Geometry (15 pts)
    # Target: 3nm at 315 deg from center
    own = data.get("ownship", {})
    try:
        olat = float(own.get("InitialLat", 0))
        olon = float(own.get("InitialLong", 0))
        brg, dist = calculate_bearing_distance(center_lat, center_lon, olat, olon)
        
        # Allow tolerances: Dist +/- 0.5nm, Brg +/- 10 deg
        dist_ok = abs(dist - 3.0) < 0.5
        brg_ok = abs(brg - 315.0) < 10.0
        
        if dist_ok and brg_ok:
            score += 15
            feedback.append(f"Ownship position correct ({dist:.1f}nm @ {brg:.0f}°).")
        else:
            feedback.append(f"Ownship position incorrect: {dist:.1f}nm @ {brg:.0f}° (Target: 3.0nm @ 315°).")
    except:
        feedback.append("Ownship data invalid.")

    # 4. Otherships Geometry (40 pts)
    others = data.get("otherships", [])
    valid_merchants = 0
    valid_escorts = 0
    
    # We expect 5 other ships
    if len(others) >= 5:
        for ship in others:
            try:
                lat = float(ship.get("InitLat", 0))
                lon = float(ship.get("InitLong", 0))
                brg, dist = calculate_bearing_distance(center_lat, center_lon, lat, lon)
                
                # Check for Guide (Center)
                if dist < 0.2:
                    valid_merchants += 1
                    continue
                
                # Check for Lead Merchant (1nm @ 045)
                if abs(dist - 1.0) < 0.3 and abs(brg - 45.0) < 10.0:
                    valid_merchants += 1
                    continue
                    
                # Check for Rear Merchant (1nm @ 225)
                if abs(dist - 1.0) < 0.3 and abs(brg - 225.0) < 10.0:
                    valid_merchants += 1
                    continue
                
                # Check for Screen Lead (3nm @ 045)
                if abs(dist - 3.0) < 0.5 and abs(brg - 45.0) < 10.0:
                    valid_escorts += 1
                    continue
                    
                # Check for Screen Stbd (3nm @ 135)
                if abs(dist - 3.0) < 0.5 and abs(brg - 135.0) < 10.0:
                    valid_escorts += 1
                    continue
            except:
                pass
    
    if valid_merchants >= 3:
        score += 20
        feedback.append("Merchant column correctly formed.")
    else:
        feedback.append(f"Merchant column flawed (found {valid_merchants}/3 valid positions).")
        
    if valid_escorts >= 2:
        score += 20
        feedback.append("Escort screen correctly placed.")
    else:
        feedback.append(f"Escort screen flawed (found {valid_escorts}/2 valid positions).")

    # 5. Config (15 pts)
    cfg = data.get("config", {})
    cfg_score = 0
    if cfg.get("arpa_on") == "1": cfg_score += 5
    if cfg.get("full_radar") == "1": cfg_score += 5
    if int(cfg.get("radar_range_resolution", 0)) >= 256: cfg_score += 5
    score += cfg_score
    if cfg_score < 15:
        feedback.append("Radar configuration incomplete.")

    # 6. Briefing (10 pts)
    brief = data.get("briefing", {})
    if brief.get("exists") and len(brief.get("keywords", [])) >= 4:
        score += 10
        feedback.append("Briefing document valid.")
    else:
        feedback.append("Briefing missing or insufficient.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }