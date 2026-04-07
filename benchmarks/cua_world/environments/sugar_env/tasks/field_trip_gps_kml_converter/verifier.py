#!/usr/bin/env python3
"""Verifier for field_trip_gps_kml_converter task."""

import json
import os
import tempfile
import xml.etree.ElementTree as ET

def verify_kml_converter(traj, env_info, task_info):
    """Verify that the CSV was correctly converted to a valid KML file."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract metadata
    metadata = task_info.get('metadata', {})
    expected_document_name = metadata.get('expected_document_name', 'Inca Trail Field Trip')

    # Read exported JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # Criterion 1: KML file exists and was modified (10 pts)
    if result.get('kml_exists'):
        if result.get('kml_modified'):
            score += 10
            feedback.append("route.kml saved during task")
        else:
            score += 5
            feedback.append("route.kml exists but might be pre-existing")
    else:
        feedback.append("FAIL: route.kml not found in /home/ga/Documents/")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Script exists (10 pts)
    if result.get('script_exists'):
        score += 10
        feedback.append(f"Script {result.get('script_name')} found")
    else:
        feedback.append("Warning: kml_generator script not found")

    # Now we need to inspect the CSV to know the expected coordinates
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/home/ga/Documents/inca_trail_track.csv", temp_csv.name)
        with open(temp_csv.name, 'r') as f:
            csv_lines = f.readlines()
    except Exception:
        csv_lines = []
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)
            
    expected_coords = []
    # Skip header
    for line in csv_lines[1:]:
        parts = line.strip().split(',')
        if len(parts) >= 4:
            lat = parts[1]
            lon = parts[2]
            ele = parts[3]
            expected_coords.append(f"{lon},{lat},{ele}")

    # Inspect the KML file
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    kml_content = ""
    try:
        copy_from_env("/home/ga/Documents/route.kml", temp_kml.name)
        with open(temp_kml.name, 'r') as f:
            kml_content = f.read()
    except Exception:
        pass
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)

    # Criterion 3: Valid XML format (20 pts)
    xml_valid = False
    root = None
    try:
        # Some xml declarations with encoding issues might fail, but let's try standard parsing
        root = ET.fromstring(kml_content)
        xml_valid = True
        score += 20
        feedback.append("KML is valid XML")
    except ET.ParseError as e:
        feedback.append(f"KML XML parsing failed: {e}")

    # Remove namespaces for easier tag checking
    def get_tag_no_ns(tag):
        if '}' in tag:
            return tag.split('}')[1]
        return tag

    has_kml = False
    has_document = False
    has_placemark = False
    has_linestring = False
    doc_name = None
    coords_text = None

    if xml_valid and root is not None:
        if get_tag_no_ns(root.tag).lower() == 'kml':
            has_kml = True
        
        for elem in root.iter():
            tag = get_tag_no_ns(elem.tag)
            if tag == 'Document':
                has_document = True
            elif tag == 'Placemark':
                has_placemark = True
            elif tag == 'LineString':
                has_linestring = True
            elif tag == 'name' and elem.text and expected_document_name in elem.text:
                doc_name = elem.text.strip()
            elif tag == 'coordinates' and elem.text:
                coords_text = elem.text.strip()

    # Criterion 4: KML Structure tags present (15 pts)
    struct_pts = 0
    if has_kml: struct_pts += 3
    if has_document: struct_pts += 4
    if has_placemark: struct_pts += 4
    if has_linestring: struct_pts += 4
    
    score += struct_pts
    if struct_pts == 15:
        feedback.append("All structural KML tags present")
    else:
        missing = []
        if not has_kml: missing.append("kml")
        if not has_document: missing.append("Document")
        if not has_placemark: missing.append("Placemark")
        if not has_linestring: missing.append("LineString")
        feedback.append(f"Missing tags: {','.join(missing)}")

    # Criterion 5: Document Name correct (5 pts)
    if doc_name == expected_document_name:
        score += 5
        feedback.append("Document name is correct")
    else:
        feedback.append("Document name mismatch or missing")

    # Parse actual coordinates
    actual_coords = []
    if coords_text:
        # Split by whitespace
        parts = coords_text.replace('\n', ' ').split()
        actual_coords = [p.strip() for p in parts if p.strip()]

    # Criterion 6: Coordinate completeness (15 pts)
    num_expected = len(expected_coords)
    num_actual = len(actual_coords)
    
    if num_expected > 0 and num_actual > 0:
        if num_actual == num_expected:
            score += 15
            feedback.append(f"Correct number of points ({num_actual})")
        elif num_actual >= num_expected * 0.9:
            score += 10
            feedback.append(f"Mostly correct number of points ({num_actual}/{num_expected})")
        else:
            feedback.append(f"Incorrect number of points ({num_actual}/{num_expected})")
    else:
        feedback.append("No coordinates found in KML")

    # Criterion 7: Coordinate ordering Lon,Lat,Elev (25 pts)
    correct_order_count = 0
    for i in range(min(num_expected, num_actual)):
        if expected_coords[i] == actual_coords[i]:
            correct_order_count += 1
            
    if num_expected > 0 and correct_order_count > 0:
        if correct_order_count == num_actual == num_expected:
            score += 25
            feedback.append("All coordinates properly formatted (Lon,Lat,Elev)")
        elif correct_order_count >= num_expected * 0.9:
            score += 15
            feedback.append("Most coordinates properly formatted")
        elif correct_order_count > 0:
            score += 5
            feedback.append(f"Some coordinates properly formatted ({correct_order_count}/{num_expected})")
    else:
        if num_actual > 0:
            # Maybe they did Lat,Lon,Elev?
            lat_lon_count = 0
            for i in range(min(num_expected, num_actual)):
                # Expected format is lon,lat,elev. Actual might be lat,lon,elev
                try:
                    exp_parts = expected_coords[i].split(',')
                    act_parts = actual_coords[i].split(',')
                    if len(act_parts) >= 2 and exp_parts[1] == act_parts[0] and exp_parts[0] == act_parts[1]:
                        lat_lon_count += 1
                except:
                    pass
            
            if lat_lon_count > 0:
                feedback.append(f"FAILED ORDERING: Found {lat_lon_count} points in Lat,Lon format instead of Lon,Lat")
            else:
                feedback.append("Coordinates mismatch (formatting or ordering incorrect)")

    # Pass threshold: 70
    passed = score >= 70 and xml_valid and struct_pts == 15 and correct_order_count >= num_expected * 0.9

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": {
            "xml_valid": xml_valid,
            "struct_correct": struct_pts == 15,
            "coords_correct": correct_order_count >= num_expected * 0.9
        }
    }