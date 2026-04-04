#!/usr/bin/env python3
"""
Verifier for pipeline_route_measurement task.

MULTI-SIGNAL VERIFICATION:
1. Output file exists (KML/KMZ) - 10 points
2. File created during task (timestamp check) - 10 points
3. Path starts near Fairbanks - 15 points
4. Path ends near Valdez - 15 points
5. Path length in valid range (550-650 km) - 20 points
6. Path passes through intermediate waypoints - 10 points
7. Sufficient waypoints in path (>15) - 5 points
8. All coordinates within Alaska bounds - 5 points
9. VLM trajectory verification - 10 points

Pass threshold: 65 points with start AND end point criteria met
"""

import json
import tempfile
import os
import logging
import math
import re
from typing import Dict, Any, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# =============================================================================
# CONSTANTS
# =============================================================================

# Fairbanks coordinates
FAIRBANKS_LAT = 64.84
FAIRBANKS_LON = -147.72

# Valdez Marine Terminal
VALDEZ_LAT = 61.13
VALDEZ_LON = -146.35

# Alaska bounds (rough)
ALASKA_LAT_MIN = 54.0
ALASKA_LAT_MAX = 72.0
ALASKA_LON_MIN = -180.0
ALASKA_LON_MAX = -130.0

# Intermediate waypoints along TAPS
INTERMEDIATE_WAYPOINTS = [
    {"name": "Delta Junction", "lat": 64.15, "lon": -145.84},
    {"name": "Isabel Pass", "lat": 63.18, "lon": -145.55},
    {"name": "Gulkana", "lat": 62.27, "lon": -145.38},
    {"name": "Thompson Pass", "lat": 61.13, "lon": -145.73},
]

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two points in kilometers using Haversine formula."""
    R = 6371  # Earth's radius in km
    
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)
    
    a = math.sin(delta_lat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def parse_kml_coordinates(kml_content: str) -> List[Tuple[float, float, float]]:
    """
    Parse coordinates from KML content.
    Returns list of (lon, lat, alt) tuples.
    """
    coordinates = []
    
    # Find all <coordinates> elements
    coord_pattern = r'<coordinates>\s*([^<]+)\s*</coordinates>'
    matches = re.findall(coord_pattern, kml_content, re.DOTALL)
    
    for match in matches:
        # Split by whitespace and parse each coordinate tuple
        coord_strings = match.strip().split()
        for coord_str in coord_strings:
            parts = coord_str.strip().split(',')
            if len(parts) >= 2:
                try:
                    lon = float(parts[0])
                    lat = float(parts[1])
                    alt = float(parts[2]) if len(parts) > 2 else 0.0
                    coordinates.append((lon, lat, alt))
                except ValueError:
                    continue
    
    return coordinates


def calculate_path_length(coordinates: List[Tuple[float, float, float]]) -> float:
    """Calculate total path length in kilometers."""
    if len(coordinates) < 2:
        return 0.0
    
    total_distance = 0.0
    for i in range(1, len(coordinates)):
        lon1, lat1, _ = coordinates[i-1]
        lon2, lat2, _ = coordinates[i]
        total_distance += haversine_distance(lat1, lon1, lat2, lon2)
    
    return total_distance


def check_point_near(point_lat: float, point_lon: float, 
                     target_lat: float, target_lon: float, 
                     tolerance_km: float) -> bool:
    """Check if a point is within tolerance distance of target."""
    distance = haversine_distance(point_lat, point_lon, target_lat, target_lon)
    return distance <= tolerance_km


def find_closest_distance_to_point(coordinates: List[Tuple[float, float, float]], 
                                   target_lat: float, target_lon: float) -> float:
    """Find the minimum distance from any path point to target."""
    if not coordinates:
        return float('inf')
    
    min_dist = float('inf')
    for lon, lat, _ in coordinates:
        dist = haversine_distance(lat, lon, target_lat, target_lon)
        min_dist = min(min_dist, dist)
    
    return min_dist


def is_in_alaska(lat: float, lon: float) -> bool:
    """Check if coordinates are within Alaska bounds."""
    return (ALASKA_LAT_MIN <= lat <= ALASKA_LAT_MAX and 
            ALASKA_LON_MIN <= lon <= ALASKA_LON_MAX)


# =============================================================================
# VLM VERIFICATION
# =============================================================================

TRAJECTORY_PROMPT = """You are verifying if an agent successfully measured the Trans-Alaska Pipeline route in Google Earth.

These images show the agent's progression through the task. Look for evidence of:

1. NAVIGATION TO ALASKA: Did the view change to show Alaska (mountainous terrain, sparse vegetation)?
2. RULER/PATH TOOL USAGE: Is there a ruler or measurement interface visible?
3. PATH CREATION: Are there measurement lines or paths being drawn on the map?
4. PIPELINE CORRIDOR: Is there a visible linear feature (cleared path through wilderness) being traced?
5. MEANINGFUL WORK: Do the frames show actual progression (not just static screens)?

The Trans-Alaska Pipeline appears as a cleared corridor running roughly north-south through Alaska's wilderness and mountains.

Respond in JSON format:
{
    "alaska_visible": true/false,
    "ruler_tool_used": true/false,
    "path_being_drawn": true/false,
    "pipeline_corridor_visible": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see in the progression"
}
"""


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def verify_pipeline_route_measurement(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the pipeline route measurement task using multiple signals.
    
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    details = {}
    score = 0
    
    # ================================================================
    # Load task result from container
    # ================================================================
    result_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_temp.name)
        with open(result_temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(result_temp.name):
            os.unlink(result_temp.name)
    
    details['task_result'] = result
    
    # ================================================================
    # CRITERION 1: Output file exists (10 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    myplaces_contains_path = result.get('myplaces_contains_path', False)
    path_coordinates_found = result.get('path_coordinates_found', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("✅ Output KML/KMZ file created")
    elif myplaces_contains_path:
        score += 7
        feedback_parts.append("⚠️ Path saved in myplaces.kml (not dedicated file)")
    else:
        feedback_parts.append("❌ No output file found")
    
    # ================================================================
    # CRITERION 2: File created during task (10 points) - anti-gaming
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    myplaces_updated = result.get('myplaces_updated', False)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task (timestamp verified)")
    elif myplaces_updated:
        score += 8
        feedback_parts.append("✅ myplaces.kml modified during task")
    else:
        feedback_parts.append("❌ No file modifications detected during task")
    
    # ================================================================
    # Load and parse KML coordinates
    # ================================================================
    coordinates = []
    kml_content = ""
    
    # Try to copy the output file
    kml_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        # Try primary output first
        try:
            copy_from_env("/tmp/pipeline_output.kml", kml_temp.name)
            with open(kml_temp.name, 'r') as f:
                kml_content = f.read()
        except:
            # Try myplaces copy
            try:
                copy_from_env("/tmp/myplaces_copy.kml", kml_temp.name)
                with open(kml_temp.name, 'r') as f:
                    kml_content = f.read()
            except:
                pass
        
        if kml_content:
            coordinates = parse_kml_coordinates(kml_content)
            logger.info(f"Parsed {len(coordinates)} coordinates from KML")
    finally:
        if os.path.exists(kml_temp.name):
            os.unlink(kml_temp.name)
    
    details['num_coordinates'] = len(coordinates)
    
    # ================================================================
    # CRITERION 3: Path starts near Fairbanks (15 points)
    # ================================================================
    start_near_fairbanks = False
    start_tolerance = metadata.get('start_tolerance_km', 50)
    
    if len(coordinates) >= 2:
        # Check first coordinate
        first_lon, first_lat, _ = coordinates[0]
        start_dist = haversine_distance(first_lat, first_lon, FAIRBANKS_LAT, FAIRBANKS_LON)
        details['start_distance_from_fairbanks_km'] = round(start_dist, 2)
        
        # Also check if any early point is near Fairbanks (first 20% of path)
        early_points = coordinates[:max(1, len(coordinates)//5)]
        min_start_dist = min(
            haversine_distance(lat, lon, FAIRBANKS_LAT, FAIRBANKS_LON)
            for lon, lat, _ in early_points
        )
        
        if min_start_dist <= start_tolerance:
            start_near_fairbanks = True
            score += 15
            feedback_parts.append(f"✅ Path starts near Fairbanks ({min_start_dist:.1f}km away)")
        else:
            feedback_parts.append(f"❌ Path start not near Fairbanks ({min_start_dist:.1f}km away)")
    else:
        feedback_parts.append("❌ Insufficient path coordinates to verify start point")
    
    # ================================================================
    # CRITERION 4: Path ends near Valdez (15 points)
    # ================================================================
    end_near_valdez = False
    end_tolerance = metadata.get('end_tolerance_km', 30)
    
    if len(coordinates) >= 2:
        # Check last coordinate
        last_lon, last_lat, _ = coordinates[-1]
        end_dist = haversine_distance(last_lat, last_lon, VALDEZ_LAT, VALDEZ_LON)
        details['end_distance_from_valdez_km'] = round(end_dist, 2)
        
        # Also check if any late point is near Valdez (last 20% of path)
        late_points = coordinates[max(0, len(coordinates) - len(coordinates)//5):]
        min_end_dist = min(
            haversine_distance(lat, lon, VALDEZ_LAT, VALDEZ_LON)
            for lon, lat, _ in late_points
        )
        
        if min_end_dist <= end_tolerance:
            end_near_valdez = True
            score += 15
            feedback_parts.append(f"✅ Path ends near Valdez ({min_end_dist:.1f}km away)")
        else:
            feedback_parts.append(f"❌ Path end not near Valdez ({min_end_dist:.1f}km away)")
    else:
        feedback_parts.append("❌ Insufficient path coordinates to verify end point")
    
    # ================================================================
    # CRITERION 5: Path length in valid range (20 points)
    # ================================================================
    path_length = calculate_path_length(coordinates)
    details['path_length_km'] = round(path_length, 2)
    
    min_length = metadata.get('min_path_length_km', 500)
    max_length = metadata.get('max_path_length_km', 700)
    
    if min_length <= path_length <= max_length:
        score += 20
        feedback_parts.append(f"✅ Path length valid ({path_length:.1f}km)")
    elif path_length > 0:
        # Partial credit for close values
        if path_length >= min_length * 0.8 and path_length <= max_length * 1.2:
            score += 10
            feedback_parts.append(f"⚠️ Path length close to expected ({path_length:.1f}km, expected {min_length}-{max_length}km)")
        else:
            feedback_parts.append(f"❌ Path length out of range ({path_length:.1f}km, expected {min_length}-{max_length}km)")
    else:
        feedback_parts.append("❌ Could not calculate path length")
    
    # ================================================================
    # CRITERION 6: Path passes through intermediate waypoints (10 points)
    # ================================================================
    waypoints_passed = 0
    waypoint_details = []
    
    for waypoint in INTERMEDIATE_WAYPOINTS:
        min_dist = find_closest_distance_to_point(
            coordinates, waypoint['lat'], waypoint['lon']
        )
        passed = min_dist <= 40  # 40km tolerance
        waypoint_details.append({
            'name': waypoint['name'],
            'distance_km': round(min_dist, 2) if min_dist != float('inf') else None,
            'passed': passed
        })
        if passed:
            waypoints_passed += 1
    
    details['intermediate_waypoints'] = waypoint_details
    
    if waypoints_passed >= 3:
        score += 10
        feedback_parts.append(f"✅ Path passes through {waypoints_passed}/4 intermediate waypoints")
    elif waypoints_passed >= 2:
        score += 7
        feedback_parts.append(f"⚠️ Path passes through {waypoints_passed}/4 intermediate waypoints")
    elif waypoints_passed >= 1:
        score += 3
        feedback_parts.append(f"⚠️ Path passes through only {waypoints_passed}/4 intermediate waypoints")
    else:
        feedback_parts.append("❌ Path doesn't pass through expected waypoints")
    
    # ================================================================
    # CRITERION 7: Sufficient waypoints (5 points)
    # ================================================================
    min_waypoints = metadata.get('min_waypoints', 15)
    
    if len(coordinates) >= min_waypoints:
        score += 5
        feedback_parts.append(f"✅ Path has {len(coordinates)} waypoints (sufficient detail)")
    elif len(coordinates) >= min_waypoints // 2:
        score += 2
        feedback_parts.append(f"⚠️ Path has {len(coordinates)} waypoints (limited detail)")
    else:
        feedback_parts.append(f"❌ Path has only {len(coordinates)} waypoints (too few)")
    
    # ================================================================
    # CRITERION 8: All coordinates within Alaska (5 points)
    # ================================================================
    if coordinates:
        in_alaska = all(is_in_alaska(lat, lon) for lon, lat, _ in coordinates)
        if in_alaska:
            score += 5
            feedback_parts.append("✅ All coordinates within Alaska bounds")
        else:
            # Count how many are in Alaska
            in_alaska_count = sum(1 for lon, lat, _ in coordinates if is_in_alaska(lat, lon))
            ratio = in_alaska_count / len(coordinates)
            if ratio >= 0.8:
                score += 3
                feedback_parts.append(f"⚠️ {ratio*100:.0f}% of coordinates in Alaska")
            else:
                feedback_parts.append(f"❌ Only {ratio*100:.0f}% of coordinates in Alaska")
    
    # ================================================================
    # CRITERION 9: VLM trajectory verification (10 points)
    # ================================================================
    vlm_score = 0
    
    if query_vlm:
        try:
            # Import trajectory frame sampling
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames across the trajectory
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if trajectory_frames or final_frame:
                frames_to_check = trajectory_frames + ([final_frame] if final_frame else [])
                
                vlm_result = query_vlm(
                    prompt=TRAJECTORY_PROMPT,
                    images=frames_to_check[:6]  # Limit to 6 frames
                )
                
                details['vlm_result'] = vlm_result
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    vlm_checks = [
                        parsed.get('alaska_visible', False),
                        parsed.get('ruler_tool_used', False),
                        parsed.get('path_being_drawn', False),
                        parsed.get('meaningful_progression', False),
                    ]
                    
                    vlm_criteria_met = sum(vlm_checks)
                    confidence = parsed.get('confidence', 'low')
                    
                    if vlm_criteria_met >= 3 and confidence in ['medium', 'high']:
                        vlm_score = 10
                        feedback_parts.append(f"✅ VLM: Work verified ({vlm_criteria_met}/4 criteria)")
                    elif vlm_criteria_met >= 2:
                        vlm_score = 6
                        feedback_parts.append(f"⚠️ VLM: Partial verification ({vlm_criteria_met}/4 criteria)")
                    else:
                        feedback_parts.append(f"❌ VLM: Limited evidence of work ({vlm_criteria_met}/4 criteria)")
                else:
                    feedback_parts.append(f"⚠️ VLM query failed: {vlm_result.get('error', 'unknown')}")
            else:
                feedback_parts.append("⚠️ No trajectory frames available for VLM verification")
        except ImportError:
            feedback_parts.append("⚠️ VLM verification not available (import error)")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append(f"⚠️ VLM verification error: {str(e)[:50]}")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    score += vlm_score
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    details['score_breakdown'] = {
        'output_exists': 10 if output_exists else (7 if myplaces_contains_path else 0),
        'file_created_during_task': 10 if file_created_during_task else (8 if myplaces_updated else 0),
        'start_near_fairbanks': 15 if start_near_fairbanks else 0,
        'end_near_valdez': 15 if end_near_valdez else 0,
        'path_length_valid': 20 if (min_length <= path_length <= max_length) else 0,
        'intermediate_waypoints': min(10, waypoints_passed * 3),
        'sufficient_waypoints': 5 if len(coordinates) >= min_waypoints else 0,
        'within_alaska': 5 if coordinates and all(is_in_alaska(lat, lon) for lon, lat, _ in coordinates) else 0,
        'vlm_verification': vlm_score
    }
    
    # Key criteria: must have start AND end points correct
    key_criteria_met = start_near_fairbanks and end_near_valdez
    
    # Pass threshold: 65 points with key criteria
    passed = score >= 65 and key_criteria_met
    
    if not key_criteria_met:
        feedback_parts.append("⚠️ KEY CRITERIA NOT MET: Path must start near Fairbanks AND end near Valdez")
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }