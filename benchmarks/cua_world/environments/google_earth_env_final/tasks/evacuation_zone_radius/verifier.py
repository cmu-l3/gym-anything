#!/usr/bin/env python3
"""
Verifier for evacuation_zone_radius task.

Task: Create a 10-mile radius emergency planning zone circle centered on
Three Mile Island Nuclear Generating Station and export it as KML.

MULTI-SIGNAL VERIFICATION:
1. KML file exists at expected path (15 points)
2. File was created during task - anti-gaming (15 points)
3. Valid KML format with polygon/circle geometry (15 points)
4. Center coordinates within tolerance of TMI location (20 points)
5. Radius within tolerance of 10 miles (15 points)
6. Appropriate naming in KML (5 points)
7. VLM trajectory verification - proves actual work (15 points)

Pass threshold: 65 points with center location criterion met
"""

import json
import tempfile
import os
import math
import logging
import re
import xml.etree.ElementTree as ET
from typing import Dict, Any, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected values from task metadata
EXPECTED_CENTER_LAT = 40.153368
EXPECTED_CENTER_LON = -76.725006
EXPECTED_RADIUS_MILES = 10.0
COORD_TOLERANCE_DEG = 0.05  # ~5.5 km
RADIUS_TOLERANCE_MILES = 1.0
KML_OUTPUT_PATH = "/home/ga/evacuation_zone.kml"


def haversine_distance_miles(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance in miles between two coordinates using Haversine formula."""
    R = 3959  # Earth's radius in miles
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))
    return R * c


def parse_kml_coordinates(kml_content: str) -> List[Tuple[float, float]]:
    """Parse KML content and extract all coordinates as (lat, lon) tuples."""
    coords_list = []
    
    # Try XML parsing first
    try:
        # Handle KML namespace
        kml_content_clean = re.sub(r'xmlns="[^"]*"', '', kml_content)
        root = ET.fromstring(kml_content_clean)
        
        # Find all coordinates elements
        for elem in root.iter():
            if 'coordinates' in elem.tag.lower() or elem.tag.endswith('coordinates'):
                if elem.text:
                    coord_text = elem.text.strip()
                    for coord in coord_text.split():
                        parts = coord.strip().split(',')
                        if len(parts) >= 2:
                            try:
                                lon = float(parts[0])
                                lat = float(parts[1])
                                coords_list.append((lat, lon))
                            except ValueError:
                                pass
    except ET.ParseError:
        pass
    
    # Fallback: regex extraction
    if not coords_list:
        coord_pattern = r'<coordinates[^>]*>\s*(.*?)\s*</coordinates>'
        matches = re.findall(coord_pattern, kml_content, re.DOTALL | re.IGNORECASE)
        for match in matches:
            for coord in match.split():
                parts = coord.strip().split(',')
                if len(parts) >= 2:
                    try:
                        lon = float(parts[0])
                        lat = float(parts[1])
                        coords_list.append((lat, lon))
                    except ValueError:
                        pass
    
    return coords_list


def analyze_circle_geometry(coords: List[Tuple[float, float]]) -> Dict[str, Any]:
    """Analyze coordinates to determine center and radius of a circle."""
    if not coords or len(coords) < 4:
        return {"valid": False, "error": "Insufficient coordinates"}
    
    # Calculate centroid
    center_lat = sum(c[0] for c in coords) / len(coords)
    center_lon = sum(c[1] for c in coords) / len(coords)
    
    # Calculate radius as average distance from center to all points
    radii = [haversine_distance_miles(center_lat, center_lon, c[0], c[1]) for c in coords]
    avg_radius = sum(radii) / len(radii)
    radius_std = (sum((r - avg_radius)**2 for r in radii) / len(radii))**0.5
    
    # Check if it's actually circular (low variance in radii)
    is_circular = radius_std < avg_radius * 0.2  # Allow 20% variance
    
    return {
        "valid": True,
        "center_lat": center_lat,
        "center_lon": center_lon,
        "radius_miles": avg_radius,
        "radius_std": radius_std,
        "is_circular": is_circular,
        "num_points": len(coords)
    }


def check_kml_naming(kml_content: str) -> bool:
    """Check if KML contains appropriate naming for the task."""
    content_lower = kml_content.lower()
    keywords = ['tmi', 'three mile', 'emergency', 'evacuation', 'zone', 'planning', 'nuclear']
    return any(kw in content_lower for kw in keywords)


# VLM Prompts
TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a task in Google Earth Pro.

TASK: Create a 10-mile radius emergency planning zone circle centered on Three Mile Island Nuclear Generating Station in Pennsylvania, USA.

The images are sampled chronologically from the agent's interaction (earliest to latest).

For successful completion, the agent should:
1. Navigate to Three Mile Island (an island in the Susquehanna River, Pennsylvania)
2. Open the measurement/ruler tool
3. Create a circle using the Circle tab
4. Set the radius and save the circle
5. Export the circle to a KML file

Assess:
1. NAVIGATION_CORRECT: Did the agent navigate to Pennsylvania/Susquehanna River area (look for river with an island)?
2. RULER_TOOL_USED: Is there evidence of the ruler/measurement dialog being opened?
3. CIRCLE_VISIBLE: Is a circle overlay visible on the map at any point?
4. WORKFLOW_PROGRESSION: Do the frames show meaningful progression through the task steps?

Respond in JSON format:
{
    "navigation_correct": true/false,
    "ruler_tool_used": true/false,
    "circle_visible": true/false,
    "workflow_progression": true/false,
    "location_observations": "describe what geographic area is visible",
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are verifying the final state of a Google Earth Pro task.

TASK: Create a 10-mile radius circle centered on Three Mile Island Nuclear Generating Station.

Look at this final screenshot and determine:
1. Is this Google Earth Pro (satellite imagery interface)?
2. Is there a visible circle overlay on the map?
3. Does the view show the Susquehanna River area in Pennsylvania (look for a river with an island)?
4. Is the circle reasonably sized for a 10-mile radius zone?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "circle_visible": true/false,
    "correct_location": true/false,
    "reasonable_size": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_evacuation_zone_radius(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the evacuation zone circle was created correctly.
    
    Uses multiple independent verification signals to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_lat = metadata.get('expected_center_lat', EXPECTED_CENTER_LAT)
    expected_lon = metadata.get('expected_center_lon', EXPECTED_CENTER_LON)
    expected_radius = metadata.get('expected_radius_miles', EXPECTED_RADIUS_MILES)
    coord_tolerance = metadata.get('coordinate_tolerance_deg', COORD_TOLERANCE_DEG)
    radius_tolerance = metadata.get('radius_tolerance_miles', RADIUS_TOLERANCE_MILES)
    kml_path = metadata.get('expected_output_path', KML_OUTPUT_PATH)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy and parse result JSON from container
    # ================================================================
    result_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_temp.name)
        with open(result_temp.name, 'r') as f:
            result = json.load(f)
        details['export_result'] = result
    except Exception as e:
        logger.warning(f"Failed to read result JSON: {e}")
        result = {}
    finally:
        if os.path.exists(result_temp.name):
            os.unlink(result_temp.name)
    
    kml_info = result.get('kml_output', {})
    
    # ================================================================
    # CRITERION 1: KML file exists (15 points)
    # ================================================================
    output_exists = kml_info.get('exists', False)
    
    if output_exists:
        score += 15
        feedback_parts.append("✅ KML file exists")
    else:
        feedback_parts.append("❌ KML file not found")
        # Can't verify much else without the file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task - anti-gaming (15 points)
    # ================================================================
    file_created_during_task = kml_info.get('created_during_task', False)
    
    if file_created_during_task:
        score += 15
        feedback_parts.append("✅ File created during task")
    else:
        feedback_parts.append("❌ File NOT created during task (pre-existing)")
    
    # ================================================================
    # CRITERION 3: Valid KML format with geometry (15 points)
    # ================================================================
    # Copy the actual KML file to analyze its contents
    kml_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    kml_content = ""
    try:
        copy_from_env(kml_path, kml_temp.name)
        with open(kml_temp.name, 'r') as f:
            kml_content = f.read()
        details['kml_size'] = len(kml_content)
    except Exception as e:
        logger.warning(f"Failed to copy KML file: {e}")
        kml_content = ""
    finally:
        if os.path.exists(kml_temp.name):
            os.unlink(kml_temp.name)
    
    valid_kml = kml_info.get('valid_kml_format', False)
    has_polygon = kml_info.get('has_polygon', False)
    has_coordinates = kml_info.get('has_coordinates', False)
    
    if valid_kml and has_polygon and has_coordinates:
        score += 15
        feedback_parts.append("✅ Valid KML with polygon geometry")
    elif valid_kml and has_coordinates:
        score += 10
        feedback_parts.append("⚠️ Valid KML but polygon structure unclear")
    elif valid_kml:
        score += 5
        feedback_parts.append("⚠️ Valid KML but missing coordinates")
    else:
        feedback_parts.append("❌ Invalid KML format")
    
    # ================================================================
    # CRITERION 4: Center coordinates correct (20 points)
    # ================================================================
    center_correct = False
    coords = parse_kml_coordinates(kml_content)
    details['parsed_coordinates_count'] = len(coords)
    
    if len(coords) >= 8:  # Need enough points for a circle
        geometry = analyze_circle_geometry(coords)
        details['geometry_analysis'] = geometry
        
        if geometry.get('valid'):
            detected_lat = geometry['center_lat']
            detected_lon = geometry['center_lon']
            
            lat_diff = abs(detected_lat - expected_lat)
            lon_diff = abs(detected_lon - expected_lon)
            
            details['center_lat_detected'] = detected_lat
            details['center_lon_detected'] = detected_lon
            details['lat_difference'] = lat_diff
            details['lon_difference'] = lon_diff
            
            if lat_diff <= coord_tolerance and lon_diff <= coord_tolerance:
                score += 20
                center_correct = True
                feedback_parts.append(f"✅ Center correct ({detected_lat:.3f}°N, {abs(detected_lon):.3f}°W)")
            else:
                feedback_parts.append(f"❌ Center incorrect (off by {lat_diff:.3f}° lat, {lon_diff:.3f}° lon)")
        else:
            feedback_parts.append("❌ Could not determine circle center")
    else:
        feedback_parts.append(f"❌ Insufficient coordinates ({len(coords)} points)")
    
    # ================================================================
    # CRITERION 5: Radius correct (15 points)
    # ================================================================
    if 'geometry_analysis' in details and details['geometry_analysis'].get('valid'):
        detected_radius = details['geometry_analysis']['radius_miles']
        radius_diff = abs(detected_radius - expected_radius)
        
        details['radius_detected'] = detected_radius
        details['radius_difference'] = radius_diff
        
        if radius_diff <= radius_tolerance:
            score += 15
            feedback_parts.append(f"✅ Radius correct ({detected_radius:.2f} miles)")
        elif radius_diff <= radius_tolerance * 2:
            score += 8
            feedback_parts.append(f"⚠️ Radius close ({detected_radius:.2f} miles, expected {expected_radius})")
        else:
            feedback_parts.append(f"❌ Radius incorrect ({detected_radius:.2f} miles, expected {expected_radius})")
    else:
        feedback_parts.append("❌ Could not determine radius")
    
    # ================================================================
    # CRITERION 6: Appropriate naming (5 points)
    # ================================================================
    has_name = kml_info.get('has_appropriate_name', False) or check_kml_naming(kml_content)
    
    if has_name:
        score += 5
        feedback_parts.append("✅ Appropriate naming")
    else:
        feedback_parts.append("⚠️ Missing expected naming keywords")
    
    # ================================================================
    # CRITERION 7: VLM trajectory verification (15 points)
    # ================================================================
    vlm_score = 0
    
    if query_vlm:
        try:
            # Import trajectory helpers
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames for process verification
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            if trajectory_frames and len(trajectory_frames) >= 2:
                # Verify trajectory shows actual work
                traj_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=trajectory_frames
                )
                
                if traj_result.get('success'):
                    parsed = traj_result.get('parsed', {})
                    details['vlm_trajectory'] = parsed
                    
                    nav_correct = parsed.get('navigation_correct', False)
                    ruler_used = parsed.get('ruler_tool_used', False)
                    circle_vis = parsed.get('circle_visible', False)
                    workflow = parsed.get('workflow_progression', False)
                    
                    traj_criteria = sum([nav_correct, ruler_used, circle_vis, workflow])
                    vlm_score = int((traj_criteria / 4) * 10)
                    
                    if traj_criteria >= 3:
                        feedback_parts.append(f"✅ VLM: Trajectory verified ({traj_criteria}/4 criteria)")
                    elif traj_criteria >= 2:
                        feedback_parts.append(f"⚠️ VLM: Partial trajectory verification ({traj_criteria}/4)")
                    else:
                        feedback_parts.append(f"❌ VLM: Trajectory verification weak ({traj_criteria}/4)")
            
            # Final state check (5 points max within VLM)
            if final_screenshot:
                final_result = query_vlm(
                    prompt=FINAL_STATE_PROMPT,
                    image=final_screenshot
                )
                
                if final_result.get('success'):
                    parsed = final_result.get('parsed', {})
                    details['vlm_final'] = parsed
                    
                    if parsed.get('circle_visible') and parsed.get('correct_location'):
                        vlm_score += 5
                        feedback_parts.append("✅ VLM: Final state shows circle at correct location")
                    elif parsed.get('circle_visible'):
                        vlm_score += 3
                        feedback_parts.append("⚠️ VLM: Circle visible, location uncertain")
                    elif parsed.get('is_google_earth'):
                        vlm_score += 1
                        feedback_parts.append("⚠️ VLM: Google Earth visible, circle not detected")
        
        except ImportError:
            logger.warning("Could not import VLM helpers")
            feedback_parts.append("⚠️ VLM verification unavailable")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM verification error: {str(e)[:50]}")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    score += vlm_score
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # Final scoring and pass determination
    # ================================================================
    max_score = 100
    details['score_breakdown'] = {
        'file_exists': 15 if output_exists else 0,
        'created_during_task': 15 if file_created_during_task else 0,
        'valid_format': 15 if (valid_kml and has_polygon) else 0,
        'center_correct': 20 if center_correct else 0,
        'radius_correct': 15 if details.get('radius_difference', 999) <= radius_tolerance else 0,
        'naming': 5 if has_name else 0,
        'vlm': vlm_score
    }
    
    # Key criteria for passing:
    # - File must be created during task (anti-gaming)
    # - Center must be at TMI location (prevents arbitrary circles)
    key_criteria_met = file_created_during_task and center_correct
    passed = score >= 65 and key_criteria_met
    
    return {
        "passed": passed,
        "score": min(score, max_score),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }