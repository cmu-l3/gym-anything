#!/usr/bin/env python3
"""
Verifier for mbta_subway_schematic task.

Scoring (100 pts total):
1. Files exist (10 pts)
2. Stations present (21 pts - 3 per station)
3. Red Line segments (15 pts)
4. Orange Line segments (15 pts)
5. Blue Line segment (10 pts)
6. Green Line segments (15 pts)
7. PNG export exists (14 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

# Official Colors (tolerant of case)
COLORS = {
    "RED": "#DA291C",
    "ORANGE": "#ED8B00",
    "BLUE": "#003DA5",
    "GREEN": "#00843D"
}

# Required Topology: (Station A, Station B, Color Key)
REQUIRED_EDGES = [
    ("downtown crossing", "south station", "RED"),
    ("downtown crossing", "park street", "RED"),
    
    ("downtown crossing", "state", "ORANGE"),
    ("haymarket", "state", "ORANGE"),
    ("haymarket", "north station", "ORANGE"),
    
    ("government center", "state", "BLUE"),
    
    ("government center", "park street", "GREEN"),
    ("government center", "haymarket", "GREEN"),
    ("haymarket", "north station", "GREEN")
]

REQUIRED_STATIONS = [
    "park street", "downtown crossing", "state", "government center",
    "haymarket", "north station", "south station"
]

def verify_mbta_subway_schematic(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Copy result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Read error: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Check (10 pts)
    if result.get('file_exists') and result.get('file_modified_after_start'):
        score += 10
        feedback.append("File saved successfully.")
    else:
        feedback.append("Draw.io file not found or not saved.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    analysis = result.get('analysis', {})
    stations_found = set(analysis.get('stations_found', []))
    connections = analysis.get('connections', [])

    # 2. Station Check (21 pts, 3 per station)
    station_points = 0
    missing_stations = []
    for st in REQUIRED_STATIONS:
        if st in stations_found:
            station_points += 3
        else:
            missing_stations.append(st)
    
    score += station_points
    if missing_stations:
        feedback.append(f"Missing stations: {', '.join(missing_stations)}")
    else:
        feedback.append("All stations found.")

    # Helper to check connections
    # connections list items look like: {'u': 'station1', 'v': 'station2', 'color': '#HEX'}
    # normalize inputs
    def check_connection(u, v, required_color_hex):
        u, v = sorted([u, v])
        required_color_hex = required_color_hex.upper()
        
        for conn in connections:
            if conn['u'] == u and conn['v'] == v:
                # Check color (allow None if just checking topology, but task requires color)
                actual_color = (conn['color'] or "").upper()
                if actual_color == required_color_hex:
                    return True
        return False

    # 3. Red Line (15 pts - 7.5 per segment)
    red_segs = 0
    if check_connection("downtown crossing", "south station", COLORS["RED"]): red_segs += 1
    if check_connection("downtown crossing", "park street", COLORS["RED"]): red_segs += 1
    
    red_score = 0
    if red_segs == 2: red_score = 15
    elif red_segs == 1: red_score = 7
    score += red_score
    feedback.append(f"Red Line: {red_segs}/2 segments correct.")

    # 4. Orange Line (15 pts - 5 per segment)
    orange_segs = 0
    if check_connection("downtown crossing", "state", COLORS["ORANGE"]): orange_segs += 1
    if check_connection("haymarket", "state", COLORS["ORANGE"]): orange_segs += 1
    if check_connection("haymarket", "north station", COLORS["ORANGE"]): orange_segs += 1
    
    score += (orange_segs * 5)
    feedback.append(f"Orange Line: {orange_segs}/3 segments correct.")

    # 5. Blue Line (10 pts)
    if check_connection("government center", "state", COLORS["BLUE"]):
        score += 10
        feedback.append("Blue Line correct.")
    else:
        feedback.append("Blue Line segment missing or wrong color.")

    # 6. Green Line (15 pts - 5 per segment)
    green_segs = 0
    if check_connection("government center", "park street", COLORS["GREEN"]): green_segs += 1
    if check_connection("government center", "haymarket", COLORS["GREEN"]): green_segs += 1
    if check_connection("haymarket", "north station", COLORS["GREEN"]): green_segs += 1
    
    score += (green_segs * 5)
    feedback.append(f"Green Line: {green_segs}/3 segments correct.")

    # 7. PNG Export (14 pts)
    if result.get('png_exists'):
        score += 14
        feedback.append("PNG export found.")
    else:
        feedback.append("PNG export missing.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }