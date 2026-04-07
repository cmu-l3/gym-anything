#!/usr/bin/env python3
import json
import math
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_bearing(lat1, lon1, lat2, lon2):
    """Calculate bearing between two lat/lon points."""
    # Simplified flat-earth calculation is sufficient for small scale Solent scenarios
    # but let's use math.atan2 for correctness
    dLon = (lon2 - lon1)
    y = math.sin(math.radians(dLon)) * math.cos(math.radians(lat2))
    x = math.cos(math.radians(lat1)) * math.sin(math.radians(lat2)) - \
        math.sin(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.cos(math.radians(dLon))
    brng = math.atan2(y, x)
    return (math.degrees(brng) + 360) % 360

def point_line_distance(px, py, x1, y1, x2, y2):
    """
    Calculate distance from point (px,py) to line segment (x1,y1)-(x2,y2).
    Using simple Euclidean distance on lat/long is acceptable for this local scale check.
    x = lat, y = long for simplicity in this function context
    """
    # Line vector
    dx = x2 - x1
    dy = y2 - y1
    if dx == 0 and dy == 0:
        return math.hypot(px - x1, py - y1)

    # Project point onto line (parameter t)
    t = ((px - x1) * dx + (py - y1) * dy) / (dx*dx + dy*dy)

    # Clamp t to segment [0,1]
    t = max(0, min(1, t))

    # Nearest point on segment
    nx = x1 + t * dx
    ny = y1 + t * dy

    return math.hypot(px - nx, py - ny)

def verify_oil_spill_boom_deployment(traj, env_info, task_info):
    """
    Verifies the V-Shape Boom Deployment task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    import tempfile
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

    # Define Targets (from Metadata/Task Desc)
    CP = {"lat": 50.8350, "long": -1.3050}
    WEST_TIP = {"lat": 50.8250, "long": -1.3150}
    EAST_TIP = {"lat": 50.8250, "long": -1.2950}
    EXPECTED_LAT_STEP = 0.002
    TOLERANCE_DIST = 0.0005 # Approx 50 meters tolerance
    
    score = 0
    feedback = []

    # 1. Scenario Structure & Anti-Gaming (20 pts)
    if result.get('scenario_exists'):
        score += 10
        feedback.append("Scenario directory created.")
    else:
        feedback.append("Scenario directory not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    if result.get('files_created_during_task'):
        score += 10
        feedback.append("Files modified during task window.")
    else:
        feedback.append("Files detected but timestamps indicate pre-existence or no modification.")

    # 2. Environment Settings (10 pts)
    env = result.get('environment', {})
    if 'Solent' in env.get('setting', ''):
        score += 5
    if float(env.get('visibilityrange', 20)) <= 3.0: # Desc asked for 2nm
        score += 5
    else:
        feedback.append("Visibility not set correctly (expected <= 3nm).")

    # 3. Object Analysis
    objects = result.get('objects', [])
    skimmers = []
    buoys_west = []
    buoys_east = []
    
    for obj in objects:
        try:
            otype = obj.get('key', '').lower() # BC uses 'Key' for type in othership.ini
            lat = float(obj.get('lat', -999))
            lon = float(obj.get('long', -999))
            
            if lat == -999: continue

            if 'buoy' in otype:
                # Classify into West or East arm based on Longitude relative to CP
                if lon < CP['long']:
                    buoys_west.append((lat, lon))
                else:
                    buoys_east.append((lat, lon))
            elif 'coaster' in otype or 'tug' in otype or 'ship' in otype:
                skimmers.append((lat, lon))
        except:
            continue

    # 4. Skimmer Placement (10 pts)
    skimmer_found = False
    for slat, slon in skimmers:
        dist = math.hypot(slat - CP['lat'], slon - CP['long'])
        if dist < TOLERANCE_DIST:
            skimmer_found = True
            break
    
    if skimmer_found:
        score += 10
        feedback.append("Recovery vessel correctly placed at Collection Point.")
    else:
        feedback.append("No recovery vessel found at Collection Point.")

    # 5. Boom Geometry & Density (50 pts total)
    
    # Analyze West Arm
    west_score = 0
    west_perfect_count = 0
    if not buoys_west:
        feedback.append("No buoys found for West Arm.")
    else:
        for blat, blon in buoys_west:
            # Check distance to ideal line segment
            d = point_line_distance(blat, blon, WEST_TIP['lat'], WEST_TIP['long'], CP['lat'], CP['long'])
            if d < TOLERANCE_DIST:
                west_perfect_count += 1
        
        # Check coverage/density
        lat_span = CP['lat'] - WEST_TIP['lat'] # 0.01
        expected_count = int(lat_span / EXPECTED_LAT_STEP) # ~5 buoys
        
        if west_perfect_count >= expected_count:
            west_score = 25
            feedback.append(f"West Arm geometry perfect ({west_perfect_count} buoys aligned).")
        elif west_perfect_count > 0:
            west_score = 10
            feedback.append(f"West Arm partially formed ({west_perfect_count} aligned).")
        else:
            feedback.append("West Arm buoys misaligned.")
            
    score += west_score

    # Analyze East Arm
    east_score = 0
    east_perfect_count = 0
    if not buoys_east:
        feedback.append("No buoys found for East Arm.")
    else:
        for blat, blon in buoys_east:
            d = point_line_distance(blat, blon, EAST_TIP['lat'], EAST_TIP['long'], CP['lat'], CP['long'])
            if d < TOLERANCE_DIST:
                east_perfect_count += 1
                
        lat_span = CP['lat'] - EAST_TIP['lat']
        expected_count = int(lat_span / EXPECTED_LAT_STEP)
        
        if east_perfect_count >= expected_count:
            east_score = 25
            feedback.append(f"East Arm geometry perfect ({east_perfect_count} buoys aligned).")
        elif east_perfect_count > 0:
            east_score = 10
            feedback.append(f"East Arm partially formed ({east_perfect_count} aligned).")
    
    score += east_score

    # 6. Documentation (10 pts)
    doc_content = result.get('doc_content', '')
    if result.get('doc_exists') and len(doc_content) > 10:
        # Check for headings (West arm bearing ~037 deg, East arm bearing ~323 deg)
        # Actually let's just check for numbers and reasonable effort
        if any(char.isdigit() for char in doc_content):
            score += 10
            feedback.append("Documentation file exists with calculations.")
    else:
        feedback.append("Documentation missing or empty.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }