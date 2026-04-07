#!/usr/bin/env python3
"""
Verifier for Lake Perimeter Measurement task.

VERIFICATION STRATEGY (Multi-Signal):
1. KML file exists and was created during task (20 points)
2. KML contains path geometry (LineString) (20 points)
3. Path is located at Crater Lake coordinates (20 points)
4. Path traces lake perimeter (closed loop with sufficient points) (20 points)
5. Total perimeter length in expected range (20 points)

BONUS: VLM trajectory verification for process evidence

Pass threshold: 60 points with key criteria (file created + correct location)
"""

import json
import tempfile
import os
import math
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected values from metadata
CRATER_LAKE_LAT = 42.94
CRATER_LAKE_LON = -122.10
LOCATION_TOLERANCE_KM = 50
MIN_PERIMETER_KM = 25.0
MAX_PERIMETER_KM = 45.0
MIN_PATH_POINTS = 15


def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in km."""
    R = 6371  # Earth radius in km
    
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)
    
    a = math.sin(delta_lat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def parse_kml_coordinates(coord_string):
    """Parse KML coordinate string into list of (lon, lat, alt) tuples."""
    coordinates = []
    if not coord_string:
        return coordinates
    
    parts = coord_string.strip().split()
    for part in parts:
        part = part.strip()
        if not part:
            continue
        values = part.split(',')
        if len(values) >= 2:
            try:
                lon = float(values[0])
                lat = float(values[1])
                alt = float(values[2]) if len(values) > 2 else 0
                coordinates.append((lon, lat, alt))
            except ValueError:
                continue
    return coordinates


def calculate_path_length(coordinates):
    """Calculate total path length in km."""
    if len(coordinates) < 2:
        return 0.0
    
    total = 0.0
    for i in range(len(coordinates) - 1):
        lon1, lat1, _ = coordinates[i]
        lon2, lat2, _ = coordinates[i + 1]
        total += haversine_distance(lat1, lon1, lat2, lon2)
    return total


def calculate_centroid(coordinates):
    """Calculate centroid of coordinates."""
    if not coordinates:
        return None, None
    avg_lon = sum(c[0] for c in coordinates) / len(coordinates)
    avg_lat = sum(c[1] for c in coordinates) / len(coordinates)
    return avg_lat, avg_lon


def is_closed_loop(coordinates, threshold_km=3.0):
    """Check if path forms a closed loop."""
    if len(coordinates) < 3:
        return False
    start = coordinates[0]
    end = coordinates[-1]
    distance = haversine_distance(start[1], start[0], end[1], end[0])
    return distance < threshold_km


def parse_kml_file(kml_content):
    """Parse KML file and extract path coordinates."""
    result = {
        "valid_xml": False,
        "has_linestring": False,
        "has_linearring": False,
        "coordinates": [],
        "error": None
    }
    
    try:
        root = ET.fromstring(kml_content)
        result["valid_xml"] = True
    except ET.ParseError as e:
        result["error"] = f"Invalid XML: {e}"
        return result
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Try to find LineString (preferred - this is what Path mode creates)
    coordinates = []
    
    # Try with namespace
    for elem in root.findall('.//kml:LineString/kml:coordinates', ns):
        if elem.text:
            coordinates = parse_kml_coordinates(elem.text)
            result["has_linestring"] = True
            break
    
    # Try without namespace
    if not coordinates:
        for elem in root.findall('.//LineString/coordinates'):
            if elem.text:
                coordinates = parse_kml_coordinates(elem.text)
                result["has_linestring"] = True
                break
    
    # Also check for LinearRing (from polygon - less ideal but acceptable)
    if not coordinates:
        for elem in root.findall('.//kml:LinearRing/kml:coordinates', ns):
            if elem.text:
                coordinates = parse_kml_coordinates(elem.text)
                result["has_linearring"] = True
                break
        
        if not coordinates:
            for elem in root.findall('.//LinearRing/coordinates'):
                if elem.text:
                    coordinates = parse_kml_coordinates(elem.text)
                    result["has_linearring"] = True
                    break
    
    result["coordinates"] = coordinates
    return result


def verify_lake_perimeter_measurement(traj, env_info, task_info):
    """
    Main verification function for Lake Perimeter Measurement task.
    
    Uses copy_from_env to retrieve files from the container.
    Uses multiple independent signals for robust verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_path', '/home/ga/Documents/crater_lake_perimeter.kml')
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy and read the task result JSON
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details["export_result"] = result
    except Exception as e:
        logger.warning(f"Could not read task result: {e}")
        result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Copy the KML file from container
    # ================================================================
    kml_content = None
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env(expected_output, temp_kml.name)
        with open(temp_kml.name, 'r') as f:
            kml_content = f.read()
        details["kml_file_copied"] = True
        details["kml_size_bytes"] = len(kml_content)
    except Exception as e:
        logger.warning(f"Could not copy KML file: {e}")
        details["kml_file_copied"] = False
        details["kml_copy_error"] = str(e)
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # CRITERION 1: KML file exists and was created during task (20 pts)
    # ================================================================
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if output_exists and file_created_during_task:
        score += 20
        feedback_parts.append("✅ KML file created during task (20/20)")
    elif output_exists:
        score += 10
        feedback_parts.append("⚠️ KML file exists but may be pre-existing (10/20)")
    elif kml_content:
        score += 15
        feedback_parts.append("⚠️ KML file found but timestamp unclear (15/20)")
    else:
        feedback_parts.append("❌ KML file not found (0/20)")
        # Can't verify further without the file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # STEP 3: Parse the KML file
    # ================================================================
    if not kml_content:
        feedback_parts.append("❌ Could not read KML content")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    kml_parsed = parse_kml_file(kml_content)
    details["kml_parsed"] = {
        "valid_xml": kml_parsed["valid_xml"],
        "has_linestring": kml_parsed["has_linestring"],
        "has_linearring": kml_parsed["has_linearring"],
        "coordinate_count": len(kml_parsed["coordinates"]),
        "error": kml_parsed.get("error")
    }
    
    coordinates = kml_parsed["coordinates"]
    
    # ================================================================
    # CRITERION 2: KML contains path geometry (20 pts)
    # ================================================================
    if kml_parsed["has_linestring"]:
        score += 20
        feedback_parts.append("✅ KML contains LineString path (20/20)")
    elif kml_parsed["has_linearring"]:
        score += 15
        feedback_parts.append("⚠️ KML contains Polygon (should be Path) (15/20)")
    elif kml_parsed["valid_xml"]:
        score += 5
        feedback_parts.append("⚠️ Valid KML but no path geometry found (5/20)")
    else:
        feedback_parts.append(f"❌ Invalid KML: {kml_parsed.get('error', 'unknown')} (0/20)")
    
    if not coordinates:
        feedback_parts.append("❌ No coordinates found in KML")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 3: Path is located at Crater Lake (20 pts)
    # ================================================================
    centroid_lat, centroid_lon = calculate_centroid(coordinates)
    details["centroid"] = {"lat": centroid_lat, "lon": centroid_lon}
    
    if centroid_lat and centroid_lon:
        distance_from_crater_lake = haversine_distance(
            centroid_lat, centroid_lon,
            CRATER_LAKE_LAT, CRATER_LAKE_LON
        )
        details["distance_from_crater_lake_km"] = distance_from_crater_lake
        
        if distance_from_crater_lake < LOCATION_TOLERANCE_KM:
            score += 20
            feedback_parts.append(f"✅ Path at Crater Lake ({distance_from_crater_lake:.1f}km from center) (20/20)")
        elif distance_from_crater_lake < LOCATION_TOLERANCE_KM * 2:
            score += 10
            feedback_parts.append(f"⚠️ Path somewhat near Crater Lake ({distance_from_crater_lake:.1f}km) (10/20)")
        else:
            feedback_parts.append(f"❌ Path not at Crater Lake ({distance_from_crater_lake:.1f}km away) (0/20)")
    else:
        feedback_parts.append("❌ Could not calculate path centroid (0/20)")
    
    # ================================================================
    # CRITERION 4: Path traces perimeter (closed loop + points) (20 pts)
    # ================================================================
    point_count = len(coordinates)
    details["point_count"] = point_count
    
    loop_closed = is_closed_loop(coordinates)
    details["loop_closed"] = loop_closed
    
    sufficient_points = point_count >= MIN_PATH_POINTS
    details["sufficient_points"] = sufficient_points
    
    path_quality_score = 0
    path_quality_feedback = []
    
    if loop_closed:
        path_quality_score += 10
        path_quality_feedback.append("closed loop")
    else:
        path_quality_feedback.append("not closed")
    
    if sufficient_points:
        path_quality_score += 10
        path_quality_feedback.append(f"{point_count} points")
    else:
        path_quality_feedback.append(f"only {point_count} points (need {MIN_PATH_POINTS}+)")
    
    score += path_quality_score
    feedback_parts.append(f"{'✅' if path_quality_score >= 15 else '⚠️' if path_quality_score >= 10 else '❌'} Path quality: {', '.join(path_quality_feedback)} ({path_quality_score}/20)")
    
    # ================================================================
    # CRITERION 5: Perimeter length in expected range (20 pts)
    # ================================================================
    path_length = calculate_path_length(coordinates)
    details["path_length_km"] = path_length
    
    if MIN_PERIMETER_KM <= path_length <= MAX_PERIMETER_KM:
        score += 20
        feedback_parts.append(f"✅ Perimeter {path_length:.1f}km in expected range (20/20)")
    elif 20 <= path_length <= 50:
        score += 10
        feedback_parts.append(f"⚠️ Perimeter {path_length:.1f}km somewhat close to expected (10/20)")
    elif path_length > 0:
        score += 5
        feedback_parts.append(f"⚠️ Perimeter {path_length:.1f}km outside expected range ({MIN_PERIMETER_KM}-{MAX_PERIMETER_KM}km) (5/20)")
    else:
        feedback_parts.append(f"❌ Could not calculate perimeter (0/20)")
    
    # ================================================================
    # VLM VERIFICATION (Bonus/Supplementary)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_bonus = 0
    
    if query_vlm:
        try:
            # Import trajectory frame helpers
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames to verify process
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            
            if frames or final:
                all_images = (frames or []) + ([final] if final else [])
                
                vlm_prompt = """You are verifying a Google Earth task where the agent was asked to:
1. Navigate to Crater Lake, Oregon
2. Use the Ruler tool in Path mode to trace the shoreline
3. Save the traced path as a KML file

Examine these screenshots from the agent's work session and determine:
1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro visible in these screenshots?
2. CRATER_LAKE_SHOWN: Is Crater Lake (a circular caldera lake in Oregon) visible?
3. RULER_TOOL_USED: Is there evidence of the Ruler tool being used (ruler dialog, path line)?
4. PATH_TRACED: Is there a path/line visible tracing around the lake?
5. WORKFLOW_PROGRESSION: Do the frames show meaningful workflow progress?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "crater_lake_shown": true/false,
    "ruler_tool_used": true/false,
    "path_traced": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_images)
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    details["vlm_verification"] = parsed
                    
                    vlm_criteria = sum([
                        parsed.get("google_earth_visible", False),
                        parsed.get("crater_lake_shown", False),
                        parsed.get("ruler_tool_used", False),
                        parsed.get("path_traced", False),
                        parsed.get("workflow_progression", False)
                    ])
                    
                    if vlm_criteria >= 4:
                        feedback_parts.append(f"✅ VLM: Process verified ({vlm_criteria}/5 criteria)")
                    elif vlm_criteria >= 2:
                        feedback_parts.append(f"⚠️ VLM: Partial process evidence ({vlm_criteria}/5 criteria)")
                    else:
                        feedback_parts.append(f"❌ VLM: Limited process evidence ({vlm_criteria}/5 criteria)")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details["vlm_error"] = str(e)
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = 100
    
    # Key criteria for passing
    file_created = result.get('output_exists', False) or (kml_content is not None)
    correct_location = details.get("distance_from_crater_lake_km", float('inf')) < LOCATION_TOLERANCE_KM
    reasonable_measurement = MIN_PERIMETER_KM * 0.5 <= path_length <= MAX_PERIMETER_KM * 1.5
    
    key_criteria_met = file_created and (correct_location or reasonable_measurement)
    
    passed = score >= 60 and key_criteria_met
    
    # Summary
    summary = f"Score: {score}/{max_score}"
    if path_length > 0:
        summary += f" | Perimeter: {path_length:.1f}km"
    if point_count > 0:
        summary += f" | Points: {point_count}"
    
    feedback_parts.insert(0, summary)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }