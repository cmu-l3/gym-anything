#!/usr/bin/env python3
"""Verifier for meteorite_kml_generator task.

Checks:
1. Python script generated and reads CSV.
2. Script avoids hardcoding (anti-gaming check).
3. KML generated and valid XML.
4. Correct filtered meteorites (Jilin, Chelyabinsk, Mbale).
5. KML Coordinates are strict lon,lat format.
6. Description contains the correct mass value.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET


def verify_meteorite_kml(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/meteorite_kml_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    task_start = result.get('task_start_ts', 0)
    
    # ---------------------------------------------------------
    # Criterion 1: Script exists & modified during task (15 pts)
    # ---------------------------------------------------------
    script_content = result.get('script_content', '')
    if result.get('script_exists') and result.get('script_size', 0) > 100:
        if result.get('script_mtime', 0) >= task_start:
            score += 15
            feedback.append("Python script created.")
        else:
            score += 5
            feedback.append("Python script exists but mtime check failed.")
    else:
        feedback.append("Python script missing or empty.")
        
    # ---------------------------------------------------------
    # Criterion 2: Anti-Gaming Check (10 pts)
    # ---------------------------------------------------------
    # Ensure they didn't just hardcode the expected outputs without parsing logic
    if script_content:
        # Check if they imported csv or used open()
        if 'csv' in script_content or 'open(' in script_content:
            score += 5
        # Check if they hardcoded the answers instead of parsing
        if 'Chelyabinsk' in script_content or 'Jilin' in script_content:
            feedback.append("Warning: Hardcoded meteorite names detected in Python script.")
        else:
            score += 5
            
    # ---------------------------------------------------------
    # Criterion 3: KML output exists (15 pts)
    # ---------------------------------------------------------
    kml_content = result.get('kml_content', '')
    if result.get('kml_exists') and result.get('kml_size', 0) > 50:
        if result.get('kml_mtime', 0) >= task_start:
            score += 15
            feedback.append("KML file created.")
        else:
            score += 5
            feedback.append("KML exists but mtime check failed.")
    else:
        feedback.append("FAIL: KML file missing or empty.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # ---------------------------------------------------------
    # Parse KML and Evaluate Contents
    # ---------------------------------------------------------
    # Remove XML namespaces to simplify searching
    clean_kml = re.sub(r'\sxmlns(:\w+)?="[^"]+"', '', kml_content)
    
    placemarks = []
    valid_xml = False
    try:
        root = ET.fromstring(clean_kml)
        valid_xml = True
        
        for pm in root.findall('.//Placemark'):
            name_elem = pm.find('.//name')
            desc_elem = pm.find('.//description')
            coords_elem = pm.find('.//coordinates')
            
            p_data = {
                'name': name_elem.text.strip() if name_elem is not None and name_elem.text else '',
                'desc': desc_elem.text.strip() if desc_elem is not None and desc_elem.text else '',
                'coords': coords_elem.text.strip() if coords_elem is not None and coords_elem.text else ''
            }
            placemarks.append(p_data)
            
    except ET.ParseError:
        feedback.append("FAIL: KML output is not valid XML.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Structure valid (10 pts)
    if valid_xml and len(placemarks) > 0:
        score += 10
        feedback.append("Valid KML structure.")
    else:
        feedback.append("No Placemarks found in KML.")

    # ---------------------------------------------------------
    # Evaluate expected placemarks
    # ---------------------------------------------------------
    expected_matches = {
        'Jilin': {'mass': '4000000', 'lon': 126.32, 'lat': 44.05},
        'Chelyabinsk': {'mass': '100000', 'lon': 60.11667, 'lat': 54.81667},
        'Mbale': {'mass': '150000', 'lon': 34.16667, 'lat': 1.06667}
    }
    
    extracted_names = [p['name'] for p in placemarks]
    
    # Check Names Exact Match (20 pts)
    names_correct = 0
    for en in expected_matches.keys():
        if en in extracted_names:
            names_correct += 1
            
    # Penalty for extra/wrong names (e.g., they failed to filter properly)
    extra_names = [n for n in extracted_names if n not in expected_matches.keys()]
    
    if names_correct == 3 and len(extra_names) == 0:
        score += 20
        feedback.append("Correct 3 meteorites filtered.")
    elif names_correct > 0:
        score += int(15 * (names_correct / 3))
        if len(extra_names) > 0:
            feedback.append(f"Filtered {names_correct}/3 correct, but included {len(extra_names)} incorrect.")
        else:
            feedback.append(f"Filtered {names_correct}/3 expected meteorites.")
    else:
        feedback.append("Did not filter expected meteorites.")
        
    # Check Coordinates (lon,lat order) and Mass (25 pts)
    coords_score = 0
    mass_score = 0
    
    for pm in placemarks:
        name = pm['name']
        if name in expected_matches:
            expected = expected_matches[name]
            
            # Mass check
            if expected['mass'] in pm['desc']:
                mass_score += 1
            
            # Coords check (strict lon, lat order)
            try:
                # KML coords are often "lon,lat" or "lon,lat,alt"
                parts = pm['coords'].split(',')
                if len(parts) >= 2:
                    lon = float(parts[0])
                    lat = float(parts[1])
                    if abs(lon - expected['lon']) < 0.1 and abs(lat - expected['lat']) < 0.1:
                        coords_score += 1
            except ValueError:
                pass
                
    if coords_score == 3:
        score += 15
        feedback.append("Coordinates perfectly formatted (lon,lat).")
    elif coords_score > 0:
        score += int(15 * (coords_score / 3))
        feedback.append("Some coordinates correct.")
        
    if mass_score == 3:
        score += 10
        feedback.append("Masses correctly included in descriptions.")
    elif mass_score > 0:
        score += int(10 * (mass_score / 3))

    passed = score >= 70 and names_correct >= 2
    if passed:
        feedback.append("KML Generation Success!")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }