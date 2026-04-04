#!/usr/bin/env python3
"""
Verifier for geofence_parameter_export task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. KML file exists at correct path (10 points)
2. File was created during task - anti-gaming (10 points)
3. Valid KML XML structure (10 points)
4. Contains polygon element with correct name (15 points)
5. Polygon location encompasses Angkor Wat (15 points)
6. Polygon size appropriate (~500m buffer) (15 points)
7. Center placemark exists with correct name (10 points)
8. Center placemark at correct location (10 points)
9. VLM trajectory verification (5 points bonus)

Pass threshold: 70 points with polygon and placemark present
"""

import json
import tempfile
import os
import math
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ================================================================
# CONSTANTS
# ================================================================

EXPECTED_OUTPUT_PATH = "/home/ga/Documents/angkor_geofence.kml"
TEMPLE_CENTER_LAT = 13.4125
TEMPLE_CENTER_LON = 103.8670
CENTER_TOLERANCE_METERS = 200

POLYGON_BOUNDS = {
    "min_lat": 13.400,
    "max_lat": 13.425,
    "min_lon": 103.850,
    "max_lon": 103.885
}

EXPECTED_AREA_MIN_KM2 = 3.0
EXPECTED_AREA_MAX_KM2 = 5.0


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two coordinates in meters."""
    R = 6371000  # Earth's radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    
    a = math.sin(dphi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def calculate_polygon_area(coords):
    """Calculate approximate polygon area in km² using shoelace formula."""
    if len(coords) < 3:
        return 0
    
    # Use average latitude for local projection
    avg_lat = sum(c[1] for c in coords) / len(coords)
    lat_scale = 111.32  # km per degree latitude
    lon_scale = 111.32 * math.cos(math.radians(avg_lat))  # km per degree longitude
    
    # Convert to local km coordinates
    local_coords = [(c[0] * lon_scale, c[1] * lat_scale) for c in coords]
    
    # Shoelace formula
    n = len(local_coords)
    area = 0.0
    for i in range(n):
        j = (i + 1) % n
        area += local_coords[i][0] * local_coords[j][1]
        area -= local_coords[j][0] * local_coords[i][1]
    
    return abs(area) / 2.0


def parse_kml_coordinates(coord_string):
    """Parse KML coordinate string into list of (lon, lat) tuples."""
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
                coords.append((lon, lat))
            except ValueError:
                continue
    return coords


def parse_kml_file(kml_content):
    """Parse KML content and extract polygon and placemark information."""
    result = {
        "valid_xml": False,
        "polygon_found": False,
        "polygon_name": "",
        "polygon_coords": [],
        "center_placemark_found": False,
        "center_placemark_name": "",
        "center_coords": None,
        "all_placemarks": []
    }
    
    try:
        root = ET.fromstring(kml_content)
        result["valid_xml"] = True
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        
        def find_all(root, tag):
            """Find elements with or without namespace."""
            elements = []
            elements.extend(root.findall(f".//{{{ns['kml']}}}{tag}"))
            elements.extend(root.findall(f".//{tag}"))
            for elem in root.iter():
                local_name = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                if local_name == tag and elem not in elements:
                    elements.append(elem)
            return elements
        
        def get_child_text(elem, tag):
            """Get text from child element."""
            for child in elem:
                local_name = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                if local_name == tag:
                    return child.text or ""
            # Also check deeper
            for child in elem.iter():
                local_name = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                if local_name == tag:
                    return child.text or ""
            return ""
        
        # Find all placemarks
        placemarks = find_all(root, "Placemark")
        
        for pm in placemarks:
            pm_name = get_child_text(pm, "name")
            result["all_placemarks"].append(pm_name)
            
            # Check for Polygon
            has_polygon = False
            for child in pm.iter():
                local_name = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                if local_name == "Polygon":
                    has_polygon = True
                    result["polygon_found"] = True
                    result["polygon_name"] = pm_name
                    
                    # Extract coordinates
                    for coord_elem in child.iter():
                        coord_name = coord_elem.tag.split('}')[-1] if '}' in coord_elem.tag else coord_elem.tag
                        if coord_name == "coordinates" and coord_elem.text:
                            coords = parse_kml_coordinates(coord_elem.text)
                            result["polygon_coords"].extend(coords)
                    break
            
            # Check for center placemark (Point, not Polygon)
            if not has_polygon:
                for child in pm.iter():
                    local_name = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                    if local_name == "Point":
                        # Check if this could be the center placemark
                        name_lower = pm_name.lower() if pm_name else ""
                        if "center" in name_lower or "geofence" in name_lower or not result["center_placemark_found"]:
                            result["center_placemark_found"] = True
                            result["center_placemark_name"] = pm_name
                            
                            # Get coordinates
                            for coord_elem in child.iter():
                                coord_name = coord_elem.tag.split('}')[-1] if '}' in coord_elem.tag else coord_elem.tag
                                if coord_name == "coordinates" and coord_elem.text:
                                    coords = parse_kml_coordinates(coord_elem.text)
                                    if coords:
                                        result["center_coords"] = coords[0]
                        break
        
    except ET.ParseError as e:
        logger.error(f"XML parse error: {e}")
    except Exception as e:
        logger.error(f"KML parsing error: {e}")
    
    return result


# ================================================================
# VLM VERIFICATION
# ================================================================

VLM_TRAJECTORY_PROMPT = """Analyze these screenshots from a Google Earth task where the agent should create a geofence around Angkor Wat temple.

The task required:
1. Navigate to Angkor Wat, Cambodia
2. Create a rectangular polygon (no-fly zone) around the temple
3. Create a center placemark
4. Save as KML file

For the screenshots, identify:
1. Is Google Earth visible?
2. Is the Angkor Wat temple complex visible (distinctive rectangular moat)?
3. Is a polygon being drawn or visible around the temple?
4. Is a placemark visible at the temple center?
5. Is a save dialog visible?
6. Does the workflow show meaningful progression?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "angkor_wat_visible": true/false,
    "polygon_visible": true/false,
    "placemark_visible": true/false,
    "save_dialog_visible": true/false,
    "meaningful_workflow": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you observe"
}
"""


def verify_via_vlm(traj, query_vlm):
    """Use VLM to verify trajectory shows proper workflow."""
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}
    
    try:
        # Import trajectory sampling utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames across the trajectory
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if not frames and not final:
            return {"success": False, "error": "No screenshots available"}
        
        # Combine frames for analysis
        all_frames = frames if frames else []
        if final and final not in all_frames:
            all_frames.append(final)
        
        if not all_frames:
            return {"success": False, "error": "No frames to analyze"}
        
        # Query VLM with trajectory frames
        result = query_vlm(prompt=VLM_TRAJECTORY_PROMPT, images=all_frames)
        
        if not result.get("success"):
            return {"success": False, "error": result.get("error", "VLM query failed")}
        
        parsed = result.get("parsed", {})
        
        # Calculate VLM score
        vlm_score = 0
        if parsed.get("google_earth_visible"):
            vlm_score += 1
        if parsed.get("angkor_wat_visible"):
            vlm_score += 2
        if parsed.get("polygon_visible"):
            vlm_score += 2
        if parsed.get("meaningful_workflow"):
            vlm_score += 1
        
        # Max 5 points from VLM
        vlm_points = min(vlm_score, 5)
        
        return {
            "success": True,
            "points": vlm_points,
            "parsed": parsed,
            "confidence": parsed.get("confidence", "low")
        }
        
    except ImportError:
        logger.warning("VLM utilities not available")
        return {"success": False, "error": "VLM utilities not imported"}
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        return {"success": False, "error": str(e)}


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_geofence_parameter_export(traj, env_info, task_info):
    """
    Verify that the geofence was correctly created and exported.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    score = 0
    max_score = 100
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: KML file exists (10 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("✅ KML file exists")
    else:
        feedback_parts.append("❌ KML file NOT found")
        # Early exit - nothing else to check
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {"file_exists": False}
        }
    
    # ================================================================
    # CRITERION 2: File created during task (10 points) - ANTI-GAMING
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task")
    else:
        feedback_parts.append("⚠️ File may have existed before task")
    
    # ================================================================
    # CRITERION 3: Valid KML XML (10 points)
    # ================================================================
    kml_valid = result.get('kml_valid_xml', False)
    
    if kml_valid:
        score += 10
        feedback_parts.append("✅ Valid KML XML")
    else:
        feedback_parts.append("❌ Invalid KML XML")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {"valid_xml": False}
        }
    
    # ================================================================
    # Copy and parse KML file for detailed analysis
    # ================================================================
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    kml_data = None
    try:
        copy_from_env("/tmp/angkor_geofence.kml", temp_kml.name)
        with open(temp_kml.name, 'r') as f:
            kml_content = f.read()
        kml_data = parse_kml_file(kml_content)
    except Exception as e:
        logger.warning(f"Could not parse KML file: {e}")
        # Try using export result data instead
        kml_data = {
            "valid_xml": True,
            "polygon_found": result.get('has_polygon_element', False),
            "polygon_name": result.get('polygon_name', ''),
            "polygon_coords": [],
            "center_placemark_found": result.get('has_center_placemark', False),
            "center_placemark_name": result.get('center_placemark_name', ''),
            "center_coords": None
        }
        # Try to parse center coords from result
        center_str = result.get('center_coords', '')
        if center_str:
            coords = parse_kml_coordinates(center_str)
            if coords:
                kml_data["center_coords"] = coords[0]
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # CRITERION 4: Polygon element with correct name (15 points)
    # ================================================================
    polygon_found = kml_data.get('polygon_found', False) if kml_data else result.get('has_polygon_element', False)
    polygon_name = kml_data.get('polygon_name', '') if kml_data else result.get('polygon_name', '')
    
    if polygon_found:
        polygon_score = 10
        name_check = polygon_name.lower() if polygon_name else ""
        if "no-fly" in name_check or "angkor" in name_check or "geofence" in name_check:
            polygon_score = 15
            feedback_parts.append(f"✅ Polygon found with name: '{polygon_name}'")
        else:
            feedback_parts.append(f"⚠️ Polygon found but name '{polygon_name}' doesn't match expected")
        score += polygon_score
    else:
        feedback_parts.append("❌ No polygon element found")
    
    # ================================================================
    # CRITERION 5: Polygon location (15 points)
    # ================================================================
    polygon_coords = kml_data.get('polygon_coords', []) if kml_data else []
    
    if polygon_coords and len(polygon_coords) >= 3:
        lons = [c[0] for c in polygon_coords]
        lats = [c[1] for c in polygon_coords]
        
        min_lon, max_lon = min(lons), max(lons)
        min_lat, max_lat = min(lats), max(lats)
        
        # Check if temple center is within polygon bounds
        temple_inside = (min_lon < TEMPLE_CENTER_LON < max_lon and 
                        min_lat < TEMPLE_CENTER_LAT < max_lat)
        
        # Check if in correct general region
        in_region = (min_lat > 13.0 and max_lat < 14.0 and 
                    min_lon > 103.0 and max_lon < 105.0)
        
        if temple_inside and in_region:
            score += 15
            feedback_parts.append("✅ Polygon correctly encompasses Angkor Wat")
        elif in_region:
            score += 8
            feedback_parts.append("⚠️ Polygon in correct region but may not encompass temple")
        else:
            feedback_parts.append("❌ Polygon not in correct location")
    else:
        feedback_parts.append("⚠️ Could not verify polygon location (no coordinates)")
    
    # ================================================================
    # CRITERION 6: Polygon size (15 points)
    # ================================================================
    if polygon_coords and len(polygon_coords) >= 3:
        area_km2 = calculate_polygon_area(polygon_coords)
        
        if EXPECTED_AREA_MIN_KM2 <= area_km2 <= EXPECTED_AREA_MAX_KM2:
            score += 15
            feedback_parts.append(f"✅ Polygon area {area_km2:.2f} km² (appropriate buffer)")
        elif 2.0 <= area_km2 <= 6.0:
            score += 10
            feedback_parts.append(f"⚠️ Polygon area {area_km2:.2f} km² (acceptable)")
        elif 1.0 <= area_km2 <= 10.0:
            score += 5
            feedback_parts.append(f"⚠️ Polygon area {area_km2:.2f} km² (questionable size)")
        else:
            feedback_parts.append(f"❌ Polygon area {area_km2:.2f} km² (incorrect)")
    else:
        feedback_parts.append("⚠️ Could not calculate polygon area")
    
    # ================================================================
    # CRITERION 7: Center placemark exists (10 points)
    # ================================================================
    center_found = kml_data.get('center_placemark_found', False) if kml_data else result.get('has_center_placemark', False)
    center_name = kml_data.get('center_placemark_name', '') if kml_data else result.get('center_placemark_name', '')
    
    if center_found:
        name_check = center_name.lower() if center_name else ""
        if "center" in name_check or "geofence" in name_check:
            score += 10
            feedback_parts.append(f"✅ Center placemark found: '{center_name}'")
        else:
            score += 7
            feedback_parts.append(f"⚠️ Placemark found but name '{center_name}' doesn't match expected")
    else:
        feedback_parts.append("❌ Center placemark not found")
    
    # ================================================================
    # CRITERION 8: Center placemark location (10 points)
    # ================================================================
    center_coords = kml_data.get('center_coords') if kml_data else None
    
    if center_coords:
        center_lon, center_lat = center_coords
        distance = haversine_distance(center_lat, center_lon, TEMPLE_CENTER_LAT, TEMPLE_CENTER_LON)
        
        if distance <= CENTER_TOLERANCE_METERS:
            score += 10
            feedback_parts.append(f"✅ Center placemark {distance:.0f}m from temple center")
        elif distance <= 500:
            score += 7
            feedback_parts.append(f"⚠️ Center placemark {distance:.0f}m from temple (acceptable)")
        elif distance <= 1000:
            score += 3
            feedback_parts.append(f"⚠️ Center placemark {distance:.0f}m from temple (too far)")
        else:
            feedback_parts.append(f"❌ Center placemark {distance:.0f}m from temple (incorrect)")
    else:
        feedback_parts.append("⚠️ Could not verify center placemark location")
    
    # ================================================================
    # CRITERION 9: VLM trajectory verification (5 bonus points)
    # ================================================================
    vlm_result = verify_via_vlm(traj, query_vlm)
    if vlm_result.get("success"):
        vlm_points = vlm_result.get("points", 0)
        score += vlm_points
        if vlm_points > 0:
            feedback_parts.append(f"✅ VLM verified workflow (+{vlm_points})")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Key criteria: must have both polygon and some indication of completion
    key_criteria_met = (
        polygon_found and 
        file_created_during_task and
        (center_found or score >= 50)
    )
    
    # Pass threshold: 70 points with key criteria
    passed = score >= 70 and key_criteria_met
    
    # Ensure score doesn't exceed 100
    score = min(score, 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "output_exists": output_exists,
            "file_created_during_task": file_created_during_task,
            "kml_valid": kml_valid,
            "polygon_found": polygon_found,
            "polygon_name": polygon_name,
            "center_found": center_found,
            "center_name": center_name,
            "polygon_coord_count": len(polygon_coords) if polygon_coords else 0,
            "key_criteria_met": key_criteria_met
        }
    }