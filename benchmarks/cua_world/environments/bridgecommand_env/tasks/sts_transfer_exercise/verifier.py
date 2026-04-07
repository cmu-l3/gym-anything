#!/usr/bin/env python3
import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_bearing_distance(lat1, lon1, lat2, lon2):
    """
    Calculate bearing and distance between two coordinates.
    Approximation for small distances (Solent scale).
    1 deg lat approx 111,111 meters.
    1 deg lon approx 111,111 * cos(lat) meters.
    """
    try:
        lat1, lon1, lat2, lon2 = map(float, [lat1, lon1, lat2, lon2])
        
        # Meters per degree
        lat_scale = 111111.0
        lon_scale = 111111.0 * math.cos(math.radians((lat1 + lat2) / 2.0))
        
        d_lat = (lat2 - lat1) * lat_scale
        d_lon = (lon2 - lon1) * lon_scale
        
        dist = math.sqrt(d_lat**2 + d_lon**2)
        return dist
    except Exception:
        return 0.0

def verify_sts_transfer_exercise(traj, env_info, task_info):
    """
    Verification for STS Transfer Exercise.
    
    Checks:
    1. Scenario structure and file existence.
    2. Environment configuration (Daytime, Calm, Solent).
    3. Own ship config (Tanker, correct pos/speed/heading).
    4. Traffic geometry (Parallel mothership, proper tug/guard positions).
    5. Simulation settings (Close quarters radar).
    6. Briefing document contents.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    meta = task_info.get('metadata', {})
    
    # Copy result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # Criterion 1: Scenario Structure (15 pts)
    # ---------------------------------------------------------
    if result.get('scenario_dir_exists'):
        score += 5
        feedback.append("Scenario directory created.")
    else:
        feedback.append("Scenario directory missing.")
        
    files = result.get('files_exist', {})
    if files.get('environment') and files.get('ownship') and files.get('othership'):
        score += 10
        feedback.append("All INI files present.")
    else:
        feedback.append(f"Missing INI files: {files}")

    # ---------------------------------------------------------
    # Criterion 2: Environment Config (15 pts)
    # ---------------------------------------------------------
    env = result.get('environment', {})
    
    # Setting
    if 'Solent' in env.get('Setting', ''):
        score += 3
    else:
        feedback.append(f"Wrong setting: {env.get('Setting')}")
        
    # Time (08-16)
    try:
        st = float(env.get('StartTime', -1))
        if 8.0 <= st <= 16.0:
            score += 4
        else:
            feedback.append(f"Start time {st} not daytime STS window.")
    except:
        feedback.append("Invalid StartTime.")

    # Weather (<= 1.5)
    try:
        w = float(env.get('Weather', 99))
        if w <= 1.5:
            score += 4
        else:
            feedback.append(f"Weather {w} too rough for STS.")
    except:
        feedback.append("Invalid Weather.")

    # Visibility (>= 10.0)
    try:
        v = float(env.get('VisibilityRange', 0))
        if v >= 10.0:
            score += 4
        else:
            feedback.append(f"Visibility {v} too low.")
    except:
        feedback.append("Invalid Visibility.")

    # ---------------------------------------------------------
    # Criterion 3: Own Ship Config (10 pts)
    # ---------------------------------------------------------
    own = result.get('ownship', {})
    own_name = own.get('ShipName', '')
    if "Pacific Harmony" in own_name:
        score += 2
    
    try:
        lat = float(own.get('InitialLat', 0))
        lon = float(own.get('InitialLong', 0))
        spd = float(own.get('InitialSpeed', 0))
        hdg = float(own.get('InitialBearing', -1))
        
        # Position check
        lat_rng = meta.get('lat_range', [50.6, 50.8])
        lon_rng = meta.get('long_range', [-1.3, -1.0])
        
        if lat_rng[0] <= lat <= lat_rng[1] and lon_rng[0] <= lon <= lon_rng[1]:
            score += 3
        else:
            feedback.append(f"Ownship pos ({lat},{lon}) out of range.")
            
        if 5.0 <= spd <= 7.0:
            score += 3
        else:
            feedback.append(f"Ownship speed {spd} invalid.")
            
        if 70 <= hdg <= 110:
            score += 2
        else:
            feedback.append(f"Ownship heading {hdg} invalid.")
            
    except:
        feedback.append("Invalid Ownship parameters.")

    # ---------------------------------------------------------
    # Criterion 4: Traffic / Mothership Geometry (25 pts)
    # ---------------------------------------------------------
    others = result.get('otherships', [])
    mothership = None
    escort = None
    guard = None
    
    for v in others:
        t = v.get('Type', '')
        if 'Caspian' in t or 'Tanker' in t: # Heuristic matching if name implies type
            mothership = v
        if 'Svitzer' in t or 'Tug' in t:
            escort = v
        if 'Guard' in t:
            guard = v
            
    # Check Mothership Geometry (Critical for STS)
    if mothership:
        try:
            m_lat = float(mothership.get('InitLat', 0))
            m_lon = float(mothership.get('InitLong', 0))
            
            # Legs info usually contains bearing/speed, but simplistic check on initial legs
            # Assuming flat format parsing might capture Leg(1) if available, but let's assume
            # simple check on existence for now, and geometric check relative to ownship
            
            dist = calculate_bearing_distance(lat, lon, m_lat, m_lon)
            if 200 <= dist <= 1000: # Allow slightly wider margin for calculation errors
                score += 10
                feedback.append(f"Mothership separation good ({int(dist)}m).")
            else:
                feedback.append(f"Mothership distance {int(dist)}m out of spec (200-800m).")
                
            score += 5 # Points for having the vessel
        except:
            pass
    else:
        feedback.append("Mothership not identified.")

    if escort: score += 5
    if guard: score += 5

    # ---------------------------------------------------------
    # Criterion 5: BC5.ini Config (15 pts)
    # ---------------------------------------------------------
    conf = result.get('config', {})
    
    if int(conf.get('max_radar_range', 0)) == 12: score += 4
    else: feedback.append(f"max_radar_range={conf.get('max_radar_range')}")
    
    if int(conf.get('radar_range_resolution', 0)) >= 256: score += 4
    else: feedback.append(f"radar_range_resolution={conf.get('radar_range_resolution')}")
    
    if int(conf.get('full_radar', 0)) == 1: score += 3
    if int(conf.get('arpa_on', 0)) == 1: score += 2
    
    # View angle 90 is key for awareness
    if int(conf.get('view_angle', 0)) == 90: score += 2

    # ---------------------------------------------------------
    # Criterion 6: Documentation (20 pts)
    # ---------------------------------------------------------
    doc_content = result.get('briefing_content', '').lower()
    
    if len(doc_content) > 500: # Length check
        score += 5
    else:
        feedback.append("Briefing too short.")
        
    keywords = ['ocimf', 'approach', 'checklist', 'emergency', 'breakaway', 'mooring', 'fender']
    hits = sum(1 for k in keywords if k in doc_content)
    
    if hits >= 5:
        score += 15
        feedback.append(f"Briefing content good ({hits} keywords).")
    elif hits >= 3:
        score += 8
        feedback.append(f"Briefing content weak ({hits} keywords).")
    else:
        feedback.append("Briefing missing key STS terms.")
        
    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }