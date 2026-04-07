#!/usr/bin/env python3
"""
Verifier for create_chemical_facility_map task.

Verifies:
1. KML file existence and creation timestamp.
2. Content of KML file for correct facilities and coordinates.
3. Content of KML file for exclusion of incorrect filtered items.
"""

import json
import os
import math
import logging
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_chemical_facility_map(traj, env_info, task_info):
    """
    Verify the KML output for the chemical facility map task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_facilities = metadata.get('facilities', [])
    tolerance = metadata.get('coordinate_tolerance', 0.002)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Initialize scoring
    score = 0
    feedback_parts = []
    
    # 1. Check file existence and timing (20 points)
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output KML file not found."}
    
    if not result.get('file_created_during_task', False):
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during this task session.")
        score += 5 # Reduced points
    else:
        score += 20
        feedback_parts.append("KML file created successfully.")

    # 2. Parse KML Content (80 points distributed)
    kml_content = result.get('kml_content', '')
    
    if not kml_content or kml_content == "FILE_TOO_LARGE":
        return {
            "passed": False, 
            "score": score, 
            "feedback": "KML content empty or too large to verify."
        }

    try:
        # KML usually has namespaces, we need to handle them or strip them for simple checking
        # Basic XML parsing
        root = ET.fromstring(kml_content)
        
        # Find all placemarks (ignoring namespace for simplicity in this robust verifier)
        # Using a recursive search for 'Placemark' tags locally to avoid namespace complexitites
        placemarks = []
        for elem in root.iter():
            if 'Placemark' in elem.tag:
                placemarks.append(elem)

        found_names = []
        placemark_data = []

        for p in placemarks:
            name = ""
            coords = ""
            for child in p:
                if 'name' in child.tag:
                    name = child.text
                if 'Point' in child.tag:
                    for point_child in child:
                        if 'coordinates' in point_child.tag:
                            coords = point_child.text
            
            if name:
                found_names.append(name)
                if coords:
                    # KML coords are "lon,lat,alt"
                    parts = coords.strip().split(',')
                    if len(parts) >= 2:
                        placemark_data.append({
                            'name': name,
                            'long': float(parts[0]),
                            'lat': float(parts[1])
                        })

        # Verify Specific Facilities
        
        # Westside Cold Storage (Should exist, check coords) - 25 pts
        westside = next((f for f in expected_facilities if f['name'] == "Westside Cold Storage"), None)
        westside_found = next((p for p in placemark_data if "Westside" in p['name']), None)
        
        if westside_found:
            lat_diff = abs(westside_found['lat'] - westside['lat'])
            long_diff = abs(westside_found['long'] - westside['long'])
            
            if lat_diff < tolerance and long_diff < tolerance:
                score += 25
                feedback_parts.append("Westside Cold Storage: Found with correct coordinates.")
            else:
                score += 10
                feedback_parts.append(f"Westside Cold Storage: Found but coordinates incorrect (Diff: {lat_diff:.4f}, {long_diff:.4f}).")
        else:
            feedback_parts.append("Westside Cold Storage: NOT found in KML.")

        # Northside Ice & Fuel (Should exist, check coords) - 25 pts
        northside = next((f for f in expected_facilities if f['name'] == "Northside Ice & Fuel"), None)
        northside_found = next((p for p in placemark_data if "Northside" in p['name']), None)
        
        if northside_found:
            lat_diff = abs(northside_found['lat'] - northside['lat'])
            long_diff = abs(northside_found['long'] - northside['long'])
            
            if lat_diff < tolerance and long_diff < tolerance:
                score += 25
                feedback_parts.append("Northside Ice & Fuel: Found with correct coordinates.")
            else:
                score += 10
                feedback_parts.append(f"Northside Ice & Fuel: Found but coordinates incorrect.")
        else:
            feedback_parts.append("Northside Ice & Fuel: NOT found in KML.")

        # Eastside Water Treatment (Should NOT exist - filter check) - 30 pts
        eastside_found = next((p for p in placemark_data if "Eastside" in p['name']), None)
        
        if eastside_found:
            feedback_parts.append("Eastside Water Treatment: Found in KML but should have been filtered out (it stores Chlorine, not Ammonia).")
        else:
            score += 30
            feedback_parts.append("Eastside Water Treatment: Correctly excluded/filtered.")

    except ET.ParseError:
        feedback_parts.append("Error: Generated file is not valid XML/KML.")
        score = 0
    except Exception as e:
        feedback_parts.append(f"Error during verification: {str(e)}")
        score = 0

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }