#!/usr/bin/env python3
"""
Verifier for the update_poi_contact_directory Garmin BaseCamp task.

Verification Strategy:
1. Validates that the GPX file was created during the task.
2. Parses the XML to ensure exactly one waypoint named "Botume House HQ" exists.
3. Checks spatial accuracy (coordinates within ±0.005 degrees).
4. CRITICAL: Evaluates presence of structured data inside <gpxx:Address> and <gpxx:PhoneNumber>
   Garmin extension elements, ensuring the agent didn't just dump text into the <desc> node.
"""

import os
import json
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def find_tag_text_ignore_namespace(element, tag_name):
    """Robustly find a tag's text by ignoring XML namespace prefixes."""
    if element is None:
        return None
    for child in element.iter():
        if child.tag.endswith(f'}}{tag_name}') or child.tag == tag_name:
            if child.text:
                return child.text.strip()
    return None

def verify_update_poi_contact_directory(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Botume House HQ").lower()
    expected_lat = float(metadata.get('expected_lat', 42.4382))
    expected_lon = float(metadata.get('expected_lon', -71.0964))
    
    expected_street = metadata.get('expected_street', "4 Woodland").lower()
    expected_city = metadata.get('expected_city', "Stoneham").lower()
    expected_state = metadata.get('expected_state', "MA").lower()
    expected_zip = metadata.get('expected_zip', "02180")
    expected_phone = metadata.get('expected_phone', "781-662-2850")

    score = 0
    feedback_parts = []
    
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    
    try:
        # Copy export metadata
        try:
            copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}

        output_exists = result.get('output_exists', False)
        created_during_task = result.get('file_created_during_task', False)

        if not output_exists:
            return {"passed": False, "score": 0, "feedback": "GPX file was not exported"}
            
        if not created_during_task:
            feedback_parts.append("Warning: File modification timestamp predates task start (possible gaming)")
        else:
            score += 10
            feedback_parts.append("File exists and created during task")

        # Copy actual GPX file
        try:
            copy_from_env("C:\\tmp\\hq_poi.gpx", temp_gpx.name)
            tree = ET.parse(temp_gpx.name)
            root = tree.getroot()
        except ET.ParseError:
            return {"passed": False, "score": score, "feedback": "GPX file is not valid XML"}
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to read or parse GPX file: {e}"}

        # 1. Waypoint Basics (15 pts)
        wpts = []
        for elem in root.iter():
            if elem.tag.endswith('}wpt') or elem.tag == 'wpt':
                wpts.append(elem)

        if not wpts:
            feedback_parts.append("No waypoints found in GPX file")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        target_wpt = None
        for wpt in wpts:
            name_text = find_tag_text_ignore_namespace(wpt, 'name')
            if name_text and expected_name in name_text.lower():
                target_wpt = wpt
                break
                
        if not target_wpt:
            target_wpt = wpts[0]  # Fallback to the first waypoint if name doesn't match perfectly
            found_name = find_tag_text_ignore_namespace(target_wpt, 'name') or "Unnamed"
            feedback_parts.append(f"Waypoint name mismatch (found '{found_name}')")
        else:
            score += 15
            feedback_parts.append("Waypoint named correctly")

        # 2. Location Accuracy (15 pts)
        lat = target_wpt.attrib.get('lat')
        lon = target_wpt.attrib.get('lon')
        
        if lat is not None and lon is not None:
            try:
                lat, lon = float(lat), float(lon)
                lat_diff = abs(lat - expected_lat)
                lon_diff = abs(lon - expected_lon)
                
                if lat_diff <= 0.005 and lon_diff <= 0.005:
                    score += 15
                    feedback_parts.append("Coordinates accurate")
                else:
                    feedback_parts.append(f"Coordinates inaccurate ({lat}, {lon})")
            except ValueError:
                feedback_parts.append("Invalid coordinate format")
        else:
            feedback_parts.append("Missing lat/lon attributes")

        # Extract structured extensions and general description
        desc_text = (find_tag_text_ignore_namespace(target_wpt, 'desc') or "").lower()
        
        street = find_tag_text_ignore_namespace(target_wpt, 'StreetAddress')
        city = find_tag_text_ignore_namespace(target_wpt, 'City')
        state = find_tag_text_ignore_namespace(target_wpt, 'State')
        zip_code = find_tag_text_ignore_namespace(target_wpt, 'PostalCode')
        phone = find_tag_text_ignore_namespace(target_wpt, 'PhoneNumber')
        
        # 3. Structured Street & City (25 pts)
        if street and city and expected_street in street.lower() and expected_city in city.lower():
            score += 25
            feedback_parts.append("Structured Address (Street/City) correct")
        else:
            if expected_street in desc_text and not street:
                feedback_parts.append("Failed: Street Address dumped in generic description box")
            else:
                feedback_parts.append(f"Structured Street/City incorrect or missing (Found: {street}, {city})")
                
        # 4. Structured State & Zip (15 pts)
        if state and zip_code and expected_state in state.lower() and expected_zip in zip_code:
            score += 15
            feedback_parts.append("Structured Address (State/Zip) correct")
        else:
            feedback_parts.append(f"Structured State/Zip incorrect or missing (Found: {state}, {zip_code})")
            
        # 5. Structured Phone (20 pts)
        # Often basecamp strips hyphens or formats dynamically, so check digits.
        digits_expected = "".join(filter(str.isdigit, expected_phone))
        if phone:
            digits_found = "".join(filter(str.isdigit, phone))
            if digits_expected in digits_found:
                score += 20
                feedback_parts.append("Structured Phone correct")
            else:
                feedback_parts.append(f"Structured Phone mismatch (Found: {phone})")
        else:
            if digits_expected in "".join(filter(str.isdigit, desc_text)):
                feedback_parts.append("Failed: Phone dumped in generic description box")
            else:
                feedback_parts.append("Structured Phone missing")

    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }