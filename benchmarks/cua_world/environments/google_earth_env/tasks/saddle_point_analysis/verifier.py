#!/usr/bin/env python3
"""
Verifier for Brenner Pass Saddle Point Documentation task.

MULTI-SIGNAL VERIFICATION:
1. KML file exists at correct path (10 points)
2. File was created during task - anti-gaming (10 points)
3. Placemark name contains 'Brenner' and 'Saddle' (10 points)
4. Coordinates accurate within 2km of Brenner Pass (40 points)
5. Elevation documented in description (15 points)
6. Distance measurement documented (10 points)
7. VLM trajectory verification (5 points bonus)

Pass threshold: 60 points with coordinates at least approximately correct
"""

import json
import tempfile
import os
import re
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Target coordinates for Brenner Pass
TARGET_LAT = 47.00
TARGET_LON = 11.51

# Elevation ranges (meters and feet)
ELEVATION_MIN_M = 1300
ELEVATION_MAX_M = 1500
ELEVATION_MIN_FT = 4200
ELEVATION_MAX_FT = 4900


def parse_kml_content(kml_content: str) -> Dict[str, Any]:
    """Parse KML content and extract placemark data."""
    result = {
        "parsed": False,
        "placemark_found": False,
        "name": "",
        "description": "",
        "latitude": None,
        "longitude": None,
        "altitude": None,
        "error": None
    }
    
    try:
        root = ET.fromstring(kml_content)
        result["parsed"] = True
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        
        # Try to find Placemark with namespace
        placemark = root.find('.//kml:Placemark', ns)
        if placemark is None:
            # Try without namespace
            placemark = root.find('.//{http://www.opengis.net/kml/2.2}Placemark')
        if placemark is None:
            placemark = root.find('.//Placemark')
        
        if placemark is None:
            result["error"] = "No Placemark found in KML"
            return result
        
        result["placemark_found"] = True
        
        # Extract name
        for name_path in ['kml:name', '{http://www.opengis.net/kml/2.2}name', 'name']:
            name_elem = placemark.find(name_path, ns) if 'kml:' in name_path else placemark.find(name_path)
            if name_elem is not None and name_elem.text:
                result["name"] = name_elem.text.strip()
                break
        
        # Extract description
        for desc_path in ['kml:description', '{http://www.opengis.net/kml/2.2}description', 'description']:
            desc_elem = placemark.find(desc_path, ns) if 'kml:' in desc_path else placemark.find(desc_path)
            if desc_elem is not None and desc_elem.text:
                result["description"] = desc_elem.text.strip()
                break
        
        # Extract coordinates
        for coord_path in ['.//kml:coordinates', './/{http://www.opengis.net/kml/2.2}coordinates', './/coordinates']:
            coords_elem = placemark.find(coord_path, ns) if 'kml:' in coord_path else placemark.find(coord_path)
            if coords_elem is not None and coords_elem.text:
                coords_text = coords_elem.text.strip()
                parts = coords_text.split(',')
                if len(parts) >= 2:
                    try:
                        result["longitude"] = float(parts[0].strip())
                        result["latitude"] = float(parts[1].strip())
                        if len(parts) >= 3:
                            result["altitude"] = float(parts[2].strip())
                    except ValueError as e:
                        result["error"] = f"Failed to parse coordinates: {e}"
                break
        
    except ET.ParseError as e:
        result["error"] = f"XML parse error: {e}"
    except Exception as e:
        result["error"] = f"Unexpected error: {e}"
    
    return result


def check_name_correct(name: str) -> tuple:
    """Check if placemark name contains required keywords."""
    name_lower = name.lower()
    
    has_brenner = 'brenner' in name_lower or 'brennero' in name_lower
    has_saddle = 'saddle' in name_lower or 'pass' in name_lower or 'col' in name_lower
    
    if has_brenner and has_saddle:
        return (10, "Name correctly identifies Brenner Pass Saddle")
    elif has_brenner:
        return (5, f"Name mentions Brenner but not saddle: '{name}'")
    elif has_saddle:
        return (3, f"Name mentions saddle but not Brenner: '{name}'")
    else:
        return (0, f"Name does not identify location: '{name}'")


def check_coordinates(lat: Optional[float], lon: Optional[float], metadata: Dict) -> tuple:
    """Check if coordinates are near Brenner Pass."""
    if lat is None or lon is None:
        return (0, "Coordinates not found in placemark", False)
    
    target_lat = metadata.get('target_latitude', TARGET_LAT)
    target_lon = metadata.get('target_longitude', TARGET_LON)
    tight_tol = metadata.get('coordinate_tolerance_tight', 0.02)
    loose_tol = metadata.get('coordinate_tolerance_loose', 0.05)
    
    lat_diff = abs(lat - target_lat)
    lon_diff = abs(lon - target_lon)
    
    if lat_diff < tight_tol and lon_diff < tight_tol:
        return (40, f"Coordinates ({lat:.4f}, {lon:.4f}) are accurate (within ~2km)", True)
    elif lat_diff < loose_tol and lon_diff < loose_tol:
        return (25, f"Coordinates ({lat:.4f}, {lon:.4f}) are approximate (within ~5km)", True)
    elif lat_diff < 0.1 and lon_diff < 0.1:
        return (15, f"Coordinates ({lat:.4f}, {lon:.4f}) are in general area (within ~10km)", True)
    else:
        return (0, f"Coordinates ({lat:.4f}, {lon:.4f}) are too far from Brenner Pass", False)


def check_elevation_documented(description: str, metadata: Dict) -> tuple:
    """Check if description contains elevation data in valid range."""
    if not description:
        return (0, "No description found")
    
    min_m = metadata.get('elevation_min_meters', ELEVATION_MIN_M)
    max_m = metadata.get('elevation_max_meters', ELEVATION_MAX_M)
    min_ft = metadata.get('elevation_min_feet', ELEVATION_MIN_FT)
    max_ft = metadata.get('elevation_max_feet', ELEVATION_MAX_FT)
    
    # Extract all numbers from description
    numbers = re.findall(r'(\d+(?:,\d+)?(?:\.\d+)?)', description)
    
    for num_str in numbers:
        try:
            num = float(num_str.replace(',', ''))
            # Check meter range
            if min_m <= num <= max_m:
                return (15, f"Elevation documented: {num}m")
            # Check feet range
            if min_ft <= num <= max_ft:
                return (15, f"Elevation documented: {num}ft")
        except ValueError:
            continue
    
    # Check for elevation-related keywords
    if re.search(r'elev|altitude|height|höhe|meters|feet|m\.?s\.?l', description, re.I):
        return (7, "Elevation mentioned but value not in expected range")
    
    return (0, "No elevation data found in description")


def check_distance_documented(description: str) -> tuple:
    """Check if description contains distance measurement."""
    if not description:
        return (0, "No description found")
    
    # Look for distance patterns
    distance_patterns = [
        r'\d+\.?\d*\s*(km|kilometers?|kilometres?)',
        r'\d+\.?\d*\s*(m|meters?|metres?)\b',
        r'\d+\.?\d*\s*(mi|miles?)',
        r'\d+\.?\d*\s*(ft|feet|foot)',
        r'distance[:\s]+\d+',
        r'entfernung[:\s]+\d+',
        r'ruler',
        r'measured'
    ]
    
    for pattern in distance_patterns:
        if re.search(pattern, description, re.I):
            return (10, "Distance measurement documented")
    
    return (0, "No distance measurement found in description")


def verify_via_vlm(traj: Dict, env_info: Dict) -> tuple:
    """VLM verification using trajectory frames."""
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return (0, "VLM not available")
    
    try:
        # Import trajectory sampling functions
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames from trajectory
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        if not frames and not final:
            return (0, "No trajectory frames available")
        
        all_frames = frames + ([final] if final else [])
        
        prompt = """You are verifying if an agent documented the Brenner Pass saddle point in Google Earth.

Look at these screenshots from the agent's interaction and assess:
1. Did the agent navigate to a mountainous/Alpine terrain area?
2. Was a placemark created (placemark dialog visible at any point)?
3. Was the ruler/measurement tool used (ruler dialog or line visible)?
4. Does the final view show the Brenner Pass region (Alps, Austria-Italy border area)?

Respond in JSON format:
{
    "alpine_terrain_visible": true/false,
    "placemark_created": true/false,
    "measurement_tool_used": true/false,
    "brenner_region_shown": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
        
        result = query_vlm(prompt=prompt, images=all_frames)
        
        if not result.get("success"):
            return (0, f"VLM query failed: {result.get('error', 'unknown')}")
        
        parsed = result.get("parsed", {})
        
        criteria_met = sum([
            parsed.get("alpine_terrain_visible", False),
            parsed.get("placemark_created", False),
            parsed.get("measurement_tool_used", False),
            parsed.get("brenner_region_shown", False)
        ])
        
        confidence = parsed.get("confidence", "low")
        
        if criteria_met >= 3 and confidence in ["medium", "high"]:
            return (5, f"VLM: Workflow verified ({criteria_met}/4 criteria)")
        elif criteria_met >= 2:
            return (3, f"VLM: Partial workflow verified ({criteria_met}/4 criteria)")
        else:
            return (0, f"VLM: Insufficient evidence ({criteria_met}/4 criteria)")
            
    except ImportError:
        return (0, "VLM module not available")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        return (0, f"VLM error: {str(e)}")


def verify_saddle_point_analysis(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify Brenner Pass Saddle Point documentation task.
    
    Uses multiple independent signals:
    1. KML file existence and validity
    2. Timestamp verification (anti-gaming)
    3. Coordinate accuracy
    4. Content verification (elevation, distance)
    5. VLM trajectory verification
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/brenner_pass_saddle.kml')
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy and parse result JSON from container
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details["result_json"] = "loaded"
    except Exception as e:
        logger.warning(f"Failed to load result JSON: {e}")
        details["result_json"] = f"error: {e}"
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Copy and parse KML file
    # ================================================================
    kml_content = ""
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env(expected_path, temp_kml.name)
        with open(temp_kml.name, 'r') as f:
            kml_content = f.read()
        kml_exists = True
        kml_size = len(kml_content)
        details["kml_file"] = f"loaded ({kml_size} bytes)"
    except Exception as e:
        kml_exists = False
        kml_size = 0
        details["kml_file"] = f"not found: {e}"
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # CRITERION 1: KML file exists (10 points)
    # ================================================================
    if kml_exists and kml_size > 50:
        score += 10
        feedback_parts.append("✅ KML file exists")
    else:
        feedback_parts.append("❌ KML file not found or empty")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task - anti-gaming (10 points)
    # ================================================================
    output_info = result_data.get('output_file', {})
    file_created_during_task = output_info.get('created_during_task', False)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task")
        details["timestamp_check"] = "passed"
    else:
        feedback_parts.append("⚠️ File may predate task (timestamp check)")
        details["timestamp_check"] = "failed"
    
    # ================================================================
    # STEP 3: Parse KML content
    # ================================================================
    kml_data = parse_kml_content(kml_content)
    details["kml_parsed"] = kml_data["parsed"]
    details["placemark_found"] = kml_data["placemark_found"]
    
    if not kml_data["placemark_found"]:
        feedback_parts.append("❌ No placemark in KML")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 3: Placemark name correct (10 points)
    # ================================================================
    name_score, name_msg = check_name_correct(kml_data["name"])
    score += name_score
    if name_score >= 10:
        feedback_parts.append(f"✅ {name_msg}")
    elif name_score > 0:
        feedback_parts.append(f"⚠️ {name_msg}")
    else:
        feedback_parts.append(f"❌ {name_msg}")
    details["name"] = kml_data["name"]
    details["name_score"] = name_score
    
    # ================================================================
    # CRITERION 4: Coordinates accurate (40 points)
    # ================================================================
    coord_score, coord_msg, coord_ok = check_coordinates(
        kml_data["latitude"], 
        kml_data["longitude"],
        metadata
    )
    score += coord_score
    if coord_score >= 40:
        feedback_parts.append(f"✅ {coord_msg}")
    elif coord_score > 0:
        feedback_parts.append(f"⚠️ {coord_msg}")
    else:
        feedback_parts.append(f"❌ {coord_msg}")
    details["latitude"] = kml_data["latitude"]
    details["longitude"] = kml_data["longitude"]
    details["coordinate_score"] = coord_score
    
    # ================================================================
    # CRITERION 5: Elevation documented (15 points)
    # ================================================================
    elev_score, elev_msg = check_elevation_documented(kml_data["description"], metadata)
    score += elev_score
    if elev_score >= 15:
        feedback_parts.append(f"✅ {elev_msg}")
    elif elev_score > 0:
        feedback_parts.append(f"⚠️ {elev_msg}")
    else:
        feedback_parts.append(f"❌ {elev_msg}")
    details["elevation_score"] = elev_score
    
    # ================================================================
    # CRITERION 6: Distance measurement (10 points)
    # ================================================================
    dist_score, dist_msg = check_distance_documented(kml_data["description"])
    score += dist_score
    if dist_score >= 10:
        feedback_parts.append(f"✅ {dist_msg}")
    else:
        feedback_parts.append(f"❌ {dist_msg}")
    details["distance_score"] = dist_score
    details["description_preview"] = kml_data["description"][:200] if kml_data["description"] else ""
    
    # ================================================================
    # CRITERION 7: VLM trajectory verification (5 bonus points)
    # ================================================================
    vlm_score, vlm_msg = verify_via_vlm(traj, env_info)
    score += vlm_score
    if vlm_score > 0:
        feedback_parts.append(f"✅ {vlm_msg}")
    details["vlm_score"] = vlm_score
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    # Pass requires: 60+ points AND coordinates at least approximately correct (>= 15 points)
    coordinates_acceptable = coord_score >= 15
    passed = score >= 60 and coordinates_acceptable
    
    # Cap score at 100
    score = min(score, 100)
    
    if passed:
        feedback_parts.insert(0, f"✅ PASSED ({score}/100)")
    else:
        if not coordinates_acceptable:
            feedback_parts.insert(0, f"❌ FAILED - Coordinates not accurate ({score}/100)")
        else:
            feedback_parts.insert(0, f"❌ FAILED - Score below threshold ({score}/100)")
    
    details["final_score"] = score
    details["coordinates_acceptable"] = coordinates_acceptable
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }