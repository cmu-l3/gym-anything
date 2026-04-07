#!/usr/bin/env python3
"""
Verifier for volcano_kml_generator task.

Checks:
1. Output file exists and was modified during task (10 pts)
2. File is valid XML/KML structure (15 pts)
3. Exactly 7 Placemarks present (20 pts)
4. Placemark names match expected stratovolcanoes (20 pts)
5. Coordinates are in the correct Longitude,Latitude order (20 pts)
6. Descriptions contain the expected country and elevation (15 pts)
"""

import json
import os
import sys
import tempfile
import xml.etree.ElementTree as ET
import re

def verify_volcano_kml(traj, env_info, task_info):
    """Verify KML output file."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Ground truth mapping
    expected_data = {
        "Cotopaxi": {"country": "Ecuador", "elevation": "5897", "lon": -78.436, "lat": -0.677},
        "Fuji": {"country": "Japan", "elevation": "3776", "lon": 138.728, "lat": 35.361},
        "Popocatepetl": {"country": "Mexico", "elevation": "5393", "lon": -98.622, "lat": 19.023},
        "Kilimanjaro": {"country": "Tanzania", "elevation": "5895", "lon": 37.356, "lat": -3.065},
        "Chimborazo": {"country": "Ecuador", "elevation": "6268", "lon": -78.817, "lat": -1.467},
        "Pico de Teide": {"country": "Spain", "elevation": "3715", "lon": -16.642, "lat": 28.271},
        "Erebus": {"country": "Antarctica", "elevation": "3794", "lon": 167.17, "lat": -77.53}
    }

    # Fetch export results
    meta_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    kml_file = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    
    score = 0
    feedback = []

    try:
        copy_from_env("/tmp/volcano_kml_result.json", meta_file.name)
        with open(meta_file.name, 'r') as f:
            result = json.load(f)
            
        if not result.get('file_exists'):
            feedback.append("FAIL: /home/ga/Documents/high_stratovolcanoes.kml not found.")
            return {"passed": False, "score": 0, "feedback": "".join(feedback)}
            
        # Criterion 1: Exists and modified during task (10 pts)
        if result.get('file_modified'):
            score += 10
            feedback.append("File created/modified successfully. ")
        else:
            feedback.append("File exists but was not modified during the task window. ")
            
        # Fetch actual KML content
        copy_from_env("/home/ga/Documents/high_stratovolcanoes.kml", kml_file.name)
        with open(kml_file.name, 'r', encoding='utf-8') as f:
            kml_content = f.read()
            
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed reading files: {e}"}
    finally:
        if os.path.exists(meta_file.name): os.unlink(meta_file.name)
        if os.path.exists(kml_file.name): os.unlink(kml_file.name)

    # Criterion 2: Valid XML/KML Structure (15 pts)
    try:
        # Strip xmlns for easier parsing if present
        xml_string = re.sub(r'\sxmlns="[^"]+"', '', kml_content, count=1)
        root = ET.fromstring(xml_string)
        score += 15
        feedback.append("Valid XML structure. ")
    except ET.ParseError:
        feedback.append("FAIL: File is not valid XML. ")
        return {"passed": False, "score": score, "feedback": "".join(feedback)}

    # Parse Placemarks
    placemarks = root.findall('.//Placemark')
    
    # Criterion 3: Exactly 7 Placemarks (20 pts)
    count = len(placemarks)
    if count == 7:
        score += 20
        feedback.append("Exactly 7 Placemarks found. ")
    else:
        feedback.append(f"Found {count} Placemarks (expected 7). ")
        
    found_names = []
    correct_names_count = 0
    correct_coords_count = 0
    correct_desc_count = 0

    for pm in placemarks:
        name_node = pm.find('name')
        desc_node = pm.find('description')
        coords_node = pm.find('.//coordinates')
        
        name = name_node.text.strip() if name_node is not None and name_node.text else ""
        desc = desc_node.text.strip() if desc_node is not None and desc_node.text else ""
        coords = coords_node.text.strip() if coords_node is not None and coords_node.text else ""
        
        found_names.append(name)
        
        if name in expected_data:
            correct_names_count += 1
            exp = expected_data[name]
            
            # Criterion 5: Coordinate validation (Lon, Lat order check)
            if coords:
                parts = coords.split(',')
                if len(parts) >= 2:
                    try:
                        parsed_lon = float(parts[0].strip())
                        parsed_lat = float(parts[1].strip())
                        
                        # Validate if Lon/Lat order is correct
                        if abs(parsed_lon - exp['lon']) < 1.0 and abs(parsed_lat - exp['lat']) < 1.0:
                            correct_coords_count += 1
                        elif abs(parsed_lon - exp['lat']) < 1.0 and abs(parsed_lat - exp['lon']) < 1.0:
                            pass # Caught flipped coordinates!
                    except ValueError:
                        pass
                        
            # Criterion 6: Description validation
            if exp['country'].lower() in desc.lower() and exp['elevation'] in desc:
                correct_desc_count += 1

    # Apply proportional points
    if count > 0:
        # Names points (max 20)
        score += int((correct_names_count / 7.0) * 20)
        if correct_names_count == 7:
            feedback.append("All expected volcanoes included. ")
        else:
            feedback.append(f"{correct_names_count}/7 correct volcanoes found. ")
            
        # Coordinates points (max 20)
        score += int((correct_coords_count / 7.0) * 20)
        if correct_coords_count == 7:
            feedback.append("All coordinates in proper Longitude,Latitude format. ")
        else:
            feedback.append(f"{correct_coords_count}/7 coordinates correct (check for Lat/Lon mixup). ")
            
        # Description points (max 15)
        score += int((correct_desc_count / 7.0) * 15)
        if correct_desc_count == 7:
            feedback.append("All descriptions contain country and elevation. ")
        else:
            feedback.append(f"{correct_desc_count}/7 descriptions formatted correctly. ")

    # Passing thresholds
    passed = (score >= 70 and correct_names_count >= 5 and count > 0)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "".join(feedback),
        "subscores": {
            "valid_xml": score >= 25,
            "correct_count": count == 7,
            "correct_names": correct_names_count,
            "correct_coords": correct_coords_count
        }
    }