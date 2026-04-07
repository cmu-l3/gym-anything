#!/usr/bin/env python3
import json
import os
import math
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine_nm(lat1, lon1, lat2, lon2):
    """Calculate distance in nautical miles between two lat/lon points."""
    R = 3440.065  # Earth radius in nautical miles
    
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) * math.sin(dlat / 2) +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(dlon / 2) * math.sin(dlon / 2))
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def parse_ini_file(content):
    """
    Parses Bridge Command INI format (specifically othership.ini).
    Returns a list of dicts for vessels.
    """
    vessels = {}
    
    # Simple line-by-line parsing
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith('//') or line.startswith('#'):
            continue
            
        # Match key(index)=value or key=value
        # Example: Type(1)="Buoy" or Number=10
        match_indexed = re.match(r'([A-Za-z]+)\((\d+)\)\s*=\s*(.*)', line)
        if match_indexed:
            key, idx, val = match_indexed.groups()
            idx = int(idx)
            if idx not in vessels:
                vessels[idx] = {}
            # Strip quotes if present
            val = val.strip('"').strip("'")
            vessels[idx][key.lower()] = val
            continue
            
        # Match indexed 2D params (waypoints) e.g. Lat(1,1)=50.5
        match_2d = re.match(r'([A-Za-z]+)\((\d+),(\d+)\)\s*=\s*(.*)', line)
        if match_2d:
            key, idx, pt, val = match_2d.groups()
            idx = int(idx)
            pt = int(pt)
            if idx not in vessels:
                vessels[idx] = {}
            if 'waypoints' not in vessels[idx]:
                vessels[idx]['waypoints'] = {}
            if pt not in vessels[idx]['waypoints']:
                vessels[idx]['waypoints'][pt] = {}
            
            val = val.strip('"').strip("'")
            vessels[idx]['waypoints'][pt][key.lower()] = val
            continue

    return vessels

def verify_wind_farm_scenario(traj, env_info, task_info):
    """
    Verifies the Wind Farm Scenario task.
    
    Criteria:
    1. Files created (10 pts)
    2. 9 static turbines found (15 pts)
    3. Grid geometry: spacing ~0.5nm and centered correctly (25 pts)
    4. Guard vessel exists and patrols outside the grid (20 pts)
    5. Notice to Mariners document contains correct coords (20 pts)
    6. Environment/Ownship basic config (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_center = metadata.get('grid_center', [50.700, -1.000])
    spacing_nm = metadata.get('grid_spacing_nm', 0.5)
    
    score = 0
    feedback = []
    
    # 1. Load basic result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # Check structure
    if result.get('scenario_created') and result.get('othership_ini_exists'):
        score += 10
        feedback.append("Scenario and INI files exist.")
    else:
        return {"passed": False, "score": 0, "feedback": "Scenario directory or othership.ini missing."}

    # 2. Parse othership.ini
    temp_ini = tempfile.NamedTemporaryFile(delete=False, suffix='.ini')
    vessels = {}
    try:
        copy_from_env(result.get('othership_path'), temp_ini.name)
        with open(temp_ini.name, 'r') as f:
            content = f.read()
            vessels = parse_ini_file(content)
    except Exception as e:
        feedback.append(f"Failed to read othership.ini: {str(e)}")
    finally:
        if os.path.exists(temp_ini.name):
            os.unlink(temp_ini.name)

    # Separate static vs moving
    static_objs = []
    moving_objs = []
    
    for idx, v in vessels.items():
        try:
            lat = float(v.get('lat', 0))
            lon = float(v.get('long', 0))
            speed = float(v.get('speed', 0))
            
            # 0.1 kts tolerance for "stationary"
            if speed < 0.1:
                static_objs.append({'id': idx, 'lat': lat, 'lon': lon})
            else:
                waypoints = []
                if 'waypoints' in v:
                    for pt_idx, pt_data in v['waypoints'].items():
                        if 'lat' in pt_data and 'long' in pt_data:
                            waypoints.append((float(pt_data['lat']), float(pt_data['long'])))
                moving_objs.append({'id': idx, 'lat': lat, 'lon': lon, 'waypoints': waypoints})
        except ValueError:
            continue

    # Criterion 2: Count
    if len(static_objs) == 9:
        score += 15
        feedback.append("Found exactly 9 static turbines.")
    else:
        feedback.append(f"Found {len(static_objs)} static objects (expected 9).")
        
    # Criterion 3: Grid Geometry
    if len(static_objs) == 9:
        # Calculate center of mass
        avg_lat = sum(o['lat'] for o in static_objs) / 9
        avg_lon = sum(o['lon'] for o in static_objs) / 9
        
        dist_center = haversine_nm(avg_lat, avg_lon, expected_center[0], expected_center[1])
        if dist_center < 0.1: # 0.1 nm tolerance for center
            score += 10
            feedback.append("Grid center is correct.")
        else:
            feedback.append(f"Grid center off by {dist_center:.2f} nm.")
            
        # Verify spacing (check nearest neighbor for each point)
        spacings = []
        for i, obj1 in enumerate(static_objs):
            dists = []
            for j, obj2 in enumerate(static_objs):
                if i != j:
                    dists.append(haversine_nm(obj1['lat'], obj1['lon'], obj2['lat'], obj2['lon']))
            if dists:
                spacings.append(min(dists))
        
        # We expect nearest neighbor to be close to 0.5 nm
        avg_spacing = sum(spacings) / len(spacings)
        if 0.45 <= avg_spacing <= 0.55:
            score += 15
            feedback.append(f"Grid spacing is correct (~{avg_spacing:.3f} nm).")
        else:
            feedback.append(f"Grid spacing incorrect (avg nearest neighbor: {avg_spacing:.3f} nm).")

    # Criterion 4: Guard Vessel
    if len(moving_objs) >= 1:
        # Find if any moving object has waypoints outside the grid
        valid_guard = False
        
        # Define grid bounds (approx)
        min_lat = min(o['lat'] for o in static_objs) if static_objs else 50.69
        max_lat = max(o['lat'] for o in static_objs) if static_objs else 50.71
        min_lon = min(o['lon'] for o in static_objs) if static_objs else -1.02
        max_lon = max(o['lon'] for o in static_objs) if static_objs else -0.98
        
        for mv in moving_objs:
            # Check if waypoints encircle or are outside bounds
            # Simple check: At least one waypoint North of max_lat, one South of min_lat, etc?
            # Or just check if all waypoints are outside the bounding box
            
            if not mv['waypoints']:
                continue
                
            outside_count = 0
            for wp in mv['waypoints']:
                wp_lat, wp_lon = wp
                # Padding of 0.05 nm (~0.0008 deg)
                if (wp_lat > max_lat + 0.0008 or wp_lat < min_lat - 0.0008 or 
                    wp_lon > max_lon + 0.001 or wp_lon < min_lon - 0.001):
                    outside_count += 1
            
            if outside_count >= 3: # Arbitrary heuristic: meaningful patrol
                valid_guard = True
                break
        
        if valid_guard:
            score += 20
            feedback.append("Guard vessel found with patrol route outside grid.")
        else:
            feedback.append("Guard vessel found but patrol route insufficient or inside grid.")
    else:
        feedback.append("No moving guard vessel found.")

    # Criterion 5: Document Check
    temp_doc = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        if result.get('doc_exists'):
            copy_from_env(result.get('doc_path'), temp_doc.name)
            with open(temp_doc.name, 'r') as f:
                doc_content = f.read()
                
            # Check for coords. The grid corners should be approx:
            # Center: 50.70, -1.00
            # 0.5nm spacing -> +/- 0.5nm from center for corners of a 3x3 grid (since 3 items span 1.0nm total? No, 2 gaps)
            # 3 items: X --0.5-- X --0.5-- X. Distance from center to edge is 0.5nm.
            # So corners are +/- 0.5nm Lat and +/- 0.5nm Lon (adjusted for cos lat) from center.
            # Lat offset: 0.5/60 = 0.00833
            # Lon offset: 0.5/38 = 0.0131
            
            # Expected roughly: 50.7083, 50.6917, -1.0131, -0.9869
            # We look for numbers close to these.
            
            matches = 0
            # Simple regex for finding coordinates in text
            nums = re.findall(r'[-+]?\d*\.\d+', doc_content)
            floats = [float(n) for n in nums]
            
            # Check for presence of something near 50.708 and 50.691
            if any(abs(n - 50.708) < 0.005 for n in floats): matches += 1
            if any(abs(n - 50.691) < 0.005 for n in floats): matches += 1
            # Check for presence of something near 1.013 and 0.986 (ignoring sign typically in text, or handle neg)
            if any(abs(abs(n) - 1.013) < 0.005 for n in floats): matches += 1
            if any(abs(abs(n) - 0.986) < 0.005 for n in floats): matches += 1
            
            if matches >= 3:
                score += 20
                feedback.append("Notice to Mariners contains correct corner coordinates.")
            else:
                feedback.append("Notice to Mariners missing correct calculated coordinates.")
        else:
            feedback.append("Notice to Mariners document not found.")
    except Exception as e:
        feedback.append(f"Error verifying document: {e}")
    finally:
        if os.path.exists(temp_doc.name):
            os.unlink(temp_doc.name)

    # Criterion 6: Basic Env/Ownship (Freebie if files exist)
    if result.get('env_ini_exists') and result.get('ownship_ini_exists'):
        score += 10
        feedback.append("Environment and Ownship files present.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }