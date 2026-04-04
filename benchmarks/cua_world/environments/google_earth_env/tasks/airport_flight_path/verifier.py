#!/usr/bin/env python3
"""
Verifier for airport_flight_path task.

Task: Create a flight planning path between San Francisco International Airport (KSFO)
and Los Angeles International Airport (KLAX), saved as a KML file.

VERIFICATION STRATEGY (Multi-Signal):
1. KML file exists at expected location (10 points)
2. KML file created/modified during task - anti-gaming (10 points)
3. Valid KML format parseable as XML (10 points)
4. Path name contains airport identifiers (15 points)
5. Contains LineString geometry (15 points)
6. First point near SFO or LAX (15 points)
7. Last point near LAX or SFO (15 points)
8. Distance sanity check - approximately 480-560 km (10 points)

VLM verification on trajectory:
- Verify agent used path creation workflow
- Verify navigation to both airports

Pass threshold: 70 points AND both coordinate criteria met
"""

import json
import tempfile
import os
import logging
import math
import xml.etree.ElementTree as ET
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected coordinates
SFO_LAT, SFO_LON = 37.6213, -122.3790
LAX_LAT, LAX_LON = 33.9425, -118.4081
COORD_TOLERANCE = 0.5  # degrees
EXPECTED_DISTANCE_KM = 543
DISTANCE_TOLERANCE_KM = 50


def calculate_distance_km(lat1, lon1, lat2, lon2):
    """Calculate great circle distance between two points in km."""
    R = 6371  # Earth's radius in km
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)
    
    a = math.sin(delta_lat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def coords_match(actual_lat, actual_lon, expected_lat, expected_lon, tolerance):
    """Check if coordinates are within tolerance."""
    return (abs(actual_lat - expected_lat) <= tolerance and 
            abs(actual_lon - expected_lon) <= tolerance)


def parse_kml_coordinates(coord_string):
    """Parse KML coordinate string into list of (lat, lon) tuples.
    KML format: lon,lat,alt lon,lat,alt ...
    """
    coords = []
    if not coord_string:
        return coords
    
    parts = coord_string.strip().split()
    for part in parts:
        values = part.split(',')
        if len(values) >= 2:
            try:
                lon = float(values[0])
                lat = float(values[1])
                coords.append((lat, lon))
            except ValueError:
                continue
    return coords


def parse_kml_file(kml_content):
    """Parse KML file and extract path information."""
    result = {
        "valid_xml": False,
        "has_placemark": False,
        "path_name": None,
        "has_linestring": False,
        "coordinates": [],
        "has_description": False,
        "error": None
    }
    
    try:
        root = ET.fromstring(kml_content)
        result["valid_xml"] = True
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        
        # Try with and without namespace
        placemarks = root.findall('.//{http://www.opengis.net/kml/2.2}Placemark')
        if not placemarks:
            placemarks = root.findall('.//Placemark')
        
        if placemarks:
            result["has_placemark"] = True
            
            for pm in placemarks:
                # Get name
                name_elem = pm.find('{http://www.opengis.net/kml/2.2}name')
                if name_elem is None:
                    name_elem = pm.find('name')
                if name_elem is not None and name_elem.text:
                    result["path_name"] = name_elem.text
                
                # Get description
                desc_elem = pm.find('{http://www.opengis.net/kml/2.2}description')
                if desc_elem is None:
                    desc_elem = pm.find('description')
                if desc_elem is not None and desc_elem.text:
                    result["has_description"] = True
                
                # Get LineString
                linestring = pm.find('.//{http://www.opengis.net/kml/2.2}LineString')
                if linestring is None:
                    linestring = pm.find('.//LineString')
                
                if linestring is not None:
                    result["has_linestring"] = True
                    
                    # Get coordinates
                    coords_elem = linestring.find('{http://www.opengis.net/kml/2.2}coordinates')
                    if coords_elem is None:
                        coords_elem = linestring.find('coordinates')
                    
                    if coords_elem is not None and coords_elem.text:
                        result["coordinates"] = parse_kml_coordinates(coords_elem.text)
                    
                    # If we found a LineString with coordinates, break
                    if result["coordinates"]:
                        break
        
    except ET.ParseError as e:
        result["error"] = f"XML parse error: {str(e)}"
    except Exception as e:
        result["error"] = f"Error parsing KML: {str(e)}"
    
    return result


# VLM prompts for trajectory verification
TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a flight path in Google Earth Pro.

The task was to create a path from San Francisco International Airport (KSFO) to Los Angeles International Airport (KLAX).

For successful completion, the agent should have:
1. Opened Google Earth Pro
2. Navigated to San Francisco area (SF Bay visible)
3. Used the Add Path tool (opened a path properties dialog)
4. Navigated to Los Angeles area
5. Saved the path and exported it

Looking at these chronological screenshots, assess:

1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro interface visible?
2. SF_AREA_SHOWN: At any point, is the San Francisco Bay Area visible?
3. LA_AREA_SHOWN: At any point, is the Los Angeles area visible?
4. PATH_TOOL_USED: Is there evidence of path creation (dialog, drawn line)?
5. SAVE_DIALOG_SHOWN: Is there a save/export dialog visible at any point?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "sf_area_shown": true/false,
    "la_area_shown": true/false,
    "path_tool_used": true/false,
    "save_dialog_shown": true/false,
    "path_line_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see across the frames"
}
"""


def verify_airport_flight_path(traj, env_info, task_info):
    """
    Main verification function for airport_flight_path task.
    
    Uses multiple independent signals:
    1. Programmatic KML file verification
    2. VLM trajectory verification
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/flight_path.kml')
    
    feedback_parts = []
    details = {}
    score = 0
    max_score = 100
    
    # ================================================================
    # STEP 1: Copy result JSON from container
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details["export_result"] = result_data
    except Exception as e:
        logger.warning(f"Could not read result JSON: {e}")
        details["export_error"] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Copy and verify KML file
    # ================================================================
    kml_content = None
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env(expected_output_path, temp_kml.name)
        with open(temp_kml.name, 'r') as f:
            kml_content = f.read()
        details["kml_copied"] = True
        details["kml_size"] = len(kml_content)
    except Exception as e:
        logger.warning(f"Could not copy KML file: {e}")
        details["kml_copied"] = False
        details["kml_error"] = str(e)
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # CRITERION 1: KML file exists (10 points)
    # ================================================================
    output_exists = result_data.get('output_exists', False) or (kml_content is not None)
    
    if output_exists and kml_content:
        score += 10
        feedback_parts.append("✓ KML file exists (+10)")
        details["file_exists"] = True
    else:
        feedback_parts.append("✗ KML file not found")
        details["file_exists"] = False
        # Return early - no point checking other criteria
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task - anti-gaming (10 points)
    # ================================================================
    file_created_during_task = result_data.get('file_created_during_task', False)
    task_start = result_data.get('task_start', 0)
    output_mtime = result_data.get('output_mtime', 0)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✓ File created during task (+10)")
        details["timestamp_valid"] = True
    elif output_mtime > task_start > 0:
        score += 10
        feedback_parts.append("✓ File timestamp valid (+10)")
        details["timestamp_valid"] = True
    else:
        feedback_parts.append("✗ File may predate task (anti-gaming)")
        details["timestamp_valid"] = False
    
    # ================================================================
    # CRITERION 3: Valid KML format (10 points)
    # ================================================================
    kml_data = parse_kml_file(kml_content)
    details["kml_parse"] = kml_data
    
    if kml_data["valid_xml"]:
        score += 10
        feedback_parts.append("✓ Valid KML/XML format (+10)")
    else:
        feedback_parts.append(f"✗ Invalid KML: {kml_data.get('error', 'parse error')}")
    
    # ================================================================
    # CRITERION 4: Path name contains airport identifiers (15 points)
    # ================================================================
    path_name = kml_data.get("path_name", "") or ""
    path_name_lower = path_name.lower()
    
    name_valid = False
    if ('ksfo' in path_name_lower and 'klax' in path_name_lower):
        name_valid = True
    elif ('sfo' in path_name_lower and 'lax' in path_name_lower):
        name_valid = True
    elif ('san francisco' in path_name_lower and 'los angeles' in path_name_lower):
        name_valid = True
    
    if name_valid:
        score += 15
        feedback_parts.append(f"✓ Path name valid: '{path_name}' (+15)")
        details["name_valid"] = True
    else:
        feedback_parts.append(f"✗ Path name missing airport identifiers: '{path_name}'")
        details["name_valid"] = False
    
    # ================================================================
    # CRITERION 5: Contains LineString geometry (15 points)
    # ================================================================
    if kml_data.get("has_linestring"):
        score += 15
        feedback_parts.append("✓ Contains LineString geometry (+15)")
        details["has_linestring"] = True
    else:
        feedback_parts.append("✗ No LineString (path) geometry found")
        details["has_linestring"] = False
    
    # ================================================================
    # CRITERIA 6 & 7: Coordinate validation (15 points each)
    # ================================================================
    coordinates = kml_data.get("coordinates", [])
    details["coordinates_count"] = len(coordinates)
    
    first_point_valid = False
    last_point_valid = False
    calculated_distance = 0
    
    if len(coordinates) >= 2:
        first_lat, first_lon = coordinates[0]
        last_lat, last_lon = coordinates[-1]
        
        details["first_point"] = {"lat": first_lat, "lon": first_lon}
        details["last_point"] = {"lat": last_lat, "lon": last_lon}
        
        # Check if endpoints are near SFO or LAX (either direction is OK)
        first_near_sfo = coords_match(first_lat, first_lon, SFO_LAT, SFO_LON, COORD_TOLERANCE)
        first_near_lax = coords_match(first_lat, first_lon, LAX_LAT, LAX_LON, COORD_TOLERANCE)
        last_near_sfo = coords_match(last_lat, last_lon, SFO_LAT, SFO_LON, COORD_TOLERANCE)
        last_near_lax = coords_match(last_lat, last_lon, LAX_LAT, LAX_LON, COORD_TOLERANCE)
        
        # Path can go either direction: SFO->LAX or LAX->SFO
        if (first_near_sfo and last_near_lax) or (first_near_lax and last_near_sfo):
            first_point_valid = True
            last_point_valid = True
            score += 30
            feedback_parts.append(f"✓ Path connects airports correctly (+30)")
            details["endpoints_valid"] = True
        else:
            # Partial credit - check each endpoint
            if first_near_sfo or first_near_lax:
                first_point_valid = True
                score += 15
                location = "SFO" if first_near_sfo else "LAX"
                feedback_parts.append(f"✓ First point near {location} (+15)")
            else:
                feedback_parts.append(f"✗ First point ({first_lat:.4f}, {first_lon:.4f}) not near airports")
            
            if last_near_sfo or last_near_lax:
                last_point_valid = True
                score += 15
                location = "SFO" if last_near_sfo else "LAX"
                feedback_parts.append(f"✓ Last point near {location} (+15)")
            else:
                feedback_parts.append(f"✗ Last point ({last_lat:.4f}, {last_lon:.4f}) not near airports")
        
        # Calculate distance
        calculated_distance = calculate_distance_km(first_lat, first_lon, last_lat, last_lon)
        details["calculated_distance_km"] = round(calculated_distance, 2)
    else:
        feedback_parts.append(f"✗ Insufficient coordinates: {len(coordinates)}")
        details["endpoints_valid"] = False
    
    # ================================================================
    # CRITERION 8: Distance sanity check (10 points)
    # ================================================================
    if calculated_distance > 0:
        distance_ok = abs(calculated_distance - EXPECTED_DISTANCE_KM) <= DISTANCE_TOLERANCE_KM
        
        if distance_ok:
            score += 10
            feedback_parts.append(f"✓ Distance {calculated_distance:.1f} km matches expected (+10)")
            details["distance_valid"] = True
        else:
            feedback_parts.append(f"✗ Distance {calculated_distance:.1f} km outside expected range ({EXPECTED_DISTANCE_KM}±{DISTANCE_TOLERANCE_KM})")
            details["distance_valid"] = False
    
    # ================================================================
    # VLM TRAJECTORY VERIFICATION (bonus validation)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score_bonus = 0
    
    if query_vlm and traj:
        try:
            # Import trajectory sampling utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames across the trajectory
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                all_frames = frames + ([final_frame] if final_frame else [])
                
                vlm_result = query_vlm(
                    prompt=TRAJECTORY_PROMPT,
                    images=all_frames
                )
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    details["vlm_analysis"] = parsed
                    
                    # Count VLM criteria met
                    vlm_criteria = [
                        parsed.get("google_earth_visible", False),
                        parsed.get("sf_area_shown", False),
                        parsed.get("la_area_shown", False),
                        parsed.get("path_tool_used", False),
                        parsed.get("path_line_visible", False)
                    ]
                    
                    vlm_met = sum(vlm_criteria)
                    
                    if vlm_met >= 4:
                        feedback_parts.append(f"✓ VLM: Strong workflow evidence ({vlm_met}/5 criteria)")
                    elif vlm_met >= 2:
                        feedback_parts.append(f"~ VLM: Partial workflow evidence ({vlm_met}/5 criteria)")
                    else:
                        feedback_parts.append(f"✗ VLM: Weak workflow evidence ({vlm_met}/5 criteria)")
                    
                    details["vlm_criteria_met"] = vlm_met
                else:
                    details["vlm_error"] = vlm_result.get("error", "unknown")
                    feedback_parts.append("~ VLM verification unavailable")
        except ImportError:
            logger.info("VLM utilities not available, skipping trajectory verification")
            details["vlm_status"] = "utilities not available"
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            details["vlm_error"] = str(e)
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    # Key criteria: both endpoints must be valid for pass
    both_endpoints_valid = first_point_valid and last_point_valid
    passed = (score >= 70) and both_endpoints_valid
    
    details["final_score"] = score
    details["max_score"] = max_score
    details["both_endpoints_valid"] = both_endpoints_valid
    
    # Final feedback summary
    feedback_parts.append(f"Score: {score}/{max_score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }