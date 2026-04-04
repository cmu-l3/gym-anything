#!/usr/bin/env python3
"""
Verifier for Central Park Perimeter Measurement task.

VERIFICATION STRATEGY (Multi-Signal):
1. KML file exists and was modified during task (15 pts) - anti-gaming
2. Target path "Central_Park_Perimeter" found (15 pts)
3. Path has sufficient points (>=20) for accurate tracing (15 pts)
4. Coordinates are within Central Park bounds (20 pts)
5. Path forms closed loop (start/end within 200m) (10 pts)
6. Measured length is accurate (9.5-10.5 km) (15 pts)
7. VLM trajectory verification - shows measurement workflow (10 pts)

Pass threshold: 70 points with key criteria (path found + length accurate)
"""

import json
import tempfile
import os
import math
import logging
from typing import Dict, Any, List, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants from task metadata
EXPECTED_PATH_NAME = "Central_Park_Perimeter"
MIN_LENGTH_KM = 9.5
MAX_LENGTH_KM = 10.5
MIN_POINTS = 20

# Central Park bounding box (with tolerance)
BOUNDS = {
    "north": 40.805,  # Slightly expanded for tolerance
    "south": 40.760,
    "west": -73.986,
    "east": -73.945
}


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two points in kilometers using haversine formula."""
    R = 6371  # Earth radius in km
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))
    return R * c


def parse_coordinates(coords_raw: str) -> List[Tuple[float, float]]:
    """Parse KML coordinate string into list of (lat, lon) tuples."""
    coordinates = []
    if not coords_raw or coords_raw.strip() == "":
        return coordinates
    
    try:
        # KML format: lon,lat,alt lon,lat,alt ...
        for coord in coords_raw.strip().split():
            parts = coord.split(',')
            if len(parts) >= 2:
                lon = float(parts[0])
                lat = float(parts[1])
                coordinates.append((lat, lon))
    except Exception as e:
        logger.warning(f"Error parsing coordinates: {e}")
    
    return coordinates


def calculate_path_length(coordinates: List[Tuple[float, float]]) -> float:
    """Calculate total length of a path in kilometers."""
    if len(coordinates) < 2:
        return 0.0
    
    total = 0.0
    for i in range(len(coordinates) - 1):
        lat1, lon1 = coordinates[i]
        lat2, lon2 = coordinates[i + 1]
        total += haversine_distance(lat1, lon1, lat2, lon2)
    return total


def check_coordinates_in_bounds(coordinates: List[Tuple[float, float]], bounds: Dict) -> Tuple[bool, int]:
    """Check if coordinates fall within bounding box. Returns (all_in_bounds, count_in_bounds)."""
    if not coordinates:
        return False, 0
    
    in_bounds_count = 0
    for lat, lon in coordinates:
        if (bounds['south'] <= lat <= bounds['north'] and
            bounds['west'] <= lon <= bounds['east']):
            in_bounds_count += 1
    
    all_in_bounds = in_bounds_count == len(coordinates)
    return all_in_bounds, in_bounds_count


def check_path_closed(coordinates: List[Tuple[float, float]], threshold_km: float = 0.3) -> Tuple[bool, float]:
    """Check if path forms a closed loop. Returns (is_closed, gap_distance_km)."""
    if len(coordinates) < 3:
        return False, float('inf')
    
    first = coordinates[0]
    last = coordinates[-1]
    distance = haversine_distance(first[0], first[1], last[0], last[1])
    return distance <= threshold_km, distance


def vlm_verify_trajectory(traj: Dict[str, Any], query_vlm) -> Dict[str, Any]:
    """Use VLM to verify trajectory shows proper measurement workflow."""
    if not query_vlm:
        return {"success": False, "score": 0, "error": "VLM not available"}
    
    try:
        # Import trajectory frame sampling
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames across the trajectory
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if not frames and not final:
            return {"success": False, "score": 0, "error": "No frames available"}
        
        all_frames = frames + ([final] if final else [])
        
        prompt = """You are verifying a Google Earth task where the agent should measure Central Park's perimeter.

Analyze these trajectory screenshots (chronological order, earliest to latest) and determine:

1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro being used (satellite imagery interface)?
2. CENTRAL_PARK_VISIBLE: At any point, is Central Park in New York City visible (the large rectangular green park in Manhattan)?
3. RULER_TOOL_USED: Is there evidence of the ruler/measurement tool being used (measurement dialog, path lines on the map)?
4. PATH_DRAWN: Are there path lines or measurement markers visible around what appears to be a park boundary?
5. WORKFLOW_PROGRESSION: Do the frames show progression (navigation, then measurement setup, then drawing)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "central_park_visible": true/false,
    "ruler_tool_used": true/false,
    "path_drawn": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see across the frames"
}
"""
        
        result = query_vlm(prompt=prompt, images=all_frames)
        
        if not result.get("success"):
            return {"success": False, "score": 0, "error": result.get("error", "VLM query failed")}
        
        parsed = result.get("parsed", {})
        
        # Score based on criteria
        criteria_met = sum([
            parsed.get("google_earth_visible", False),
            parsed.get("central_park_visible", False),
            parsed.get("ruler_tool_used", False),
            parsed.get("path_drawn", False),
            parsed.get("workflow_progression", False)
        ])
        
        confidence = parsed.get("confidence", "low")
        confidence_mult = {"high": 1.0, "medium": 0.85, "low": 0.7}.get(confidence, 0.7)
        
        vlm_score = int((criteria_met / 5) * 10 * confidence_mult)
        
        return {
            "success": True,
            "score": vlm_score,
            "criteria_met": criteria_met,
            "parsed": parsed
        }
        
    except ImportError:
        logger.warning("Could not import VLM utilities, skipping trajectory verification")
        return {"success": False, "score": 0, "error": "VLM import failed"}
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        return {"success": False, "score": 0, "error": str(e)}


def verify_central_park_perimeter(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Main verification function for Central Park Perimeter task.
    
    Uses multiple independent signals to verify task completion.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }
    
    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_path_name = metadata.get('expected_path_name', EXPECTED_PATH_NAME)
    min_length = metadata.get('min_length_km', MIN_LENGTH_KM)
    max_length = metadata.get('max_length_km', MAX_LENGTH_KM)
    min_points = metadata.get('min_points', MIN_POINTS)
    
    feedback_parts = []
    details = {}
    score = 0
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        details['result_loaded'] = True
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read task result: {e}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    
    # ================================================================
    # CRITERION 1: File exists and was modified during task (15 pts)
    # ================================================================
    myplaces_exists = result.get('myplaces_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_modified = result.get('file_modified_during_task', False)
    
    if myplaces_exists and (file_created or file_modified):
        score += 15
        feedback_parts.append("✅ KML file modified during task")
        details['file_modified_during_task'] = True
    elif myplaces_exists:
        score += 5
        feedback_parts.append("⚠️ KML exists but may not have been modified during task")
        details['file_modified_during_task'] = False
    else:
        feedback_parts.append("❌ No myplaces.kml file found")
        details['file_modified_during_task'] = False
    
    # ================================================================
    # CRITERION 2: Target path found (15 pts)
    # ================================================================
    target_path_found = result.get('target_path_found', False)
    
    if target_path_found:
        score += 15
        feedback_parts.append(f"✅ Path '{expected_path_name}' found")
        details['target_path_found'] = True
    else:
        feedback_parts.append(f"❌ Path '{expected_path_name}' not found")
        details['target_path_found'] = False
    
    # ================================================================
    # CRITERION 3: Sufficient points (15 pts)
    # ================================================================
    num_coordinates = result.get('num_coordinates', 0)
    details['num_coordinates'] = num_coordinates
    
    if num_coordinates >= min_points:
        score += 15
        feedback_parts.append(f"✅ Sufficient points ({num_coordinates} >= {min_points})")
        details['sufficient_points'] = True
    elif num_coordinates >= min_points // 2:
        score += 8
        feedback_parts.append(f"⚠️ Some points but fewer than ideal ({num_coordinates} < {min_points})")
        details['sufficient_points'] = False
    elif num_coordinates > 0:
        score += 3
        feedback_parts.append(f"❌ Too few points ({num_coordinates})")
        details['sufficient_points'] = False
    else:
        feedback_parts.append("❌ No coordinates found in path")
        details['sufficient_points'] = False
    
    # Parse coordinates for further analysis
    coords_raw = result.get('coordinates_raw', '')
    coordinates = parse_coordinates(coords_raw)
    details['parsed_coordinate_count'] = len(coordinates)
    
    # ================================================================
    # CRITERION 4: Coordinates within bounds (20 pts)
    # ================================================================
    if coordinates:
        all_in_bounds, in_bounds_count = check_coordinates_in_bounds(coordinates, BOUNDS)
        details['coordinates_in_bounds'] = in_bounds_count
        details['coordinates_total'] = len(coordinates)
        
        if all_in_bounds:
            score += 20
            feedback_parts.append("✅ All coordinates within Central Park area")
            details['within_bounds'] = True
        elif in_bounds_count >= len(coordinates) * 0.8:
            score += 15
            feedback_parts.append(f"⚠️ Most coordinates in bounds ({in_bounds_count}/{len(coordinates)})")
            details['within_bounds'] = "partial"
        elif in_bounds_count > 0:
            score += 5
            feedback_parts.append(f"⚠️ Some coordinates outside bounds ({in_bounds_count}/{len(coordinates)})")
            details['within_bounds'] = False
        else:
            feedback_parts.append("❌ Coordinates not in Central Park area")
            details['within_bounds'] = False
    else:
        feedback_parts.append("❌ Cannot verify bounds - no coordinates")
        details['within_bounds'] = False
    
    # ================================================================
    # CRITERION 5: Path forms closed loop (10 pts)
    # ================================================================
    if len(coordinates) >= 3:
        is_closed, gap_distance = check_path_closed(coordinates)
        details['path_closed'] = is_closed
        details['gap_distance_km'] = round(gap_distance, 3)
        
        if is_closed:
            score += 10
            feedback_parts.append(f"✅ Path forms closed loop (gap: {gap_distance:.0f}m)")
        elif gap_distance < 1.0:
            score += 5
            feedback_parts.append(f"⚠️ Path nearly closed (gap: {gap_distance*1000:.0f}m)")
        else:
            feedback_parts.append(f"❌ Path not closed (gap: {gap_distance:.2f}km)")
    else:
        feedback_parts.append("❌ Cannot check closure - too few points")
        details['path_closed'] = False
    
    # ================================================================
    # CRITERION 6: Length accuracy (15 pts)
    # ================================================================
    if len(coordinates) >= 2:
        path_length = calculate_path_length(coordinates)
        details['measured_length_km'] = round(path_length, 2)
        
        if min_length <= path_length <= max_length:
            score += 15
            feedback_parts.append(f"✅ Accurate perimeter: {path_length:.2f} km")
            details['length_accurate'] = True
        elif min_length * 0.8 <= path_length <= max_length * 1.2:
            score += 10
            feedback_parts.append(f"⚠️ Perimeter close: {path_length:.2f} km (expected {min_length}-{max_length} km)")
            details['length_accurate'] = "close"
        elif path_length > 0:
            score += 3
            feedback_parts.append(f"❌ Perimeter off: {path_length:.2f} km (expected {min_length}-{max_length} km)")
            details['length_accurate'] = False
        else:
            feedback_parts.append("❌ Could not calculate path length")
            details['length_accurate'] = False
    else:
        feedback_parts.append("❌ Cannot calculate length - insufficient coordinates")
        details['length_accurate'] = False
        details['measured_length_km'] = 0
    
    # ================================================================
    # CRITERION 7: VLM trajectory verification (10 pts)
    # ================================================================
    vlm_result = vlm_verify_trajectory(traj, query_vlm)
    details['vlm_verification'] = vlm_result
    
    if vlm_result.get('success'):
        vlm_score = vlm_result.get('score', 0)
        score += vlm_score
        if vlm_score >= 7:
            feedback_parts.append(f"✅ VLM verified workflow ({vlm_score}/10)")
        elif vlm_score >= 4:
            feedback_parts.append(f"⚠️ VLM partial verification ({vlm_score}/10)")
        else:
            feedback_parts.append(f"❌ VLM low score ({vlm_score}/10)")
    else:
        feedback_parts.append("⚠️ VLM verification unavailable")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    # Key criteria that must be met for passing
    key_criteria_met = (
        target_path_found and 
        details.get('length_accurate') in [True, "close"] and
        (file_created or file_modified)
    )
    
    passed = score >= 70 and key_criteria_met
    
    # Compile feedback
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }