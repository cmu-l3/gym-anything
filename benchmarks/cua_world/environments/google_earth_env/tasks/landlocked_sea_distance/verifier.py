#!/usr/bin/env python3
"""
Verifier for landlocked_sea_distance task.

Task: Measure the shortest straight-line distance from Ulaanbaatar, Mongolia
      (Sükhbaatar Square) to the nearest ocean coastline (Bohai Sea).

Verification Strategy:
1. Screenshot exists and was created during task (15 points)
2. Screenshot file size reasonable (5 points)
3. myplaces.kml modified during task (10 points)
4. Measurement coordinates found in KML (20 points)
5. Start point near Ulaanbaatar (15 points)
6. End point near coastline region (15 points)
7. VLM trajectory verification - workflow shown (10 points)
8. VLM final screenshot - measurement visible (10 points)

Pass threshold: 60 points with key criteria (screenshot exists + some measurement evidence)
"""

import json
import tempfile
import os
import math
import logging
from typing import Dict, Any, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth data
ULAANBAATAR_CENTER = (47.9184, 106.9177)  # Sükhbaatar Square lat, lon
START_TOLERANCE_KM = 15  # How close to city center the start must be
EXPECTED_DISTANCE_MIN = 650  # km
EXPECTED_DISTANCE_MAX = 750  # km

# Coastline region (Bohai Sea area in northeastern China)
COASTLINE_REGION = {
    "lat_min": 38.0,
    "lat_max": 42.0,
    "lon_min": 117.0,
    "lon_max": 125.0
}


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two points in km using Haversine formula."""
    R = 6371  # Earth's radius in km
    
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)
    
    a = math.sin(delta_lat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def is_near_ulaanbaatar(lat: float, lon: float, tolerance_km: float = START_TOLERANCE_KM) -> bool:
    """Check if coordinates are near Ulaanbaatar city center."""
    distance = haversine_distance(lat, lon, ULAANBAATAR_CENTER[0], ULAANBAATAR_CENTER[1])
    return distance <= tolerance_km


def is_in_coastline_region(lat: float, lon: float) -> bool:
    """Check if coordinates are in the expected coastline region (Bohai Sea)."""
    return (COASTLINE_REGION["lat_min"] <= lat <= COASTLINE_REGION["lat_max"] and
            COASTLINE_REGION["lon_min"] <= lon <= COASTLINE_REGION["lon_max"])


def analyze_coordinates(coords_data: List[Dict]) -> Dict[str, Any]:
    """Analyze extracted coordinates to find the measurement line."""
    result = {
        "measurement_found": False,
        "start_coords": None,
        "end_coords": None,
        "start_near_ulaanbaatar": False,
        "end_near_coastline": False,
        "calculated_distance_km": None,
        "distance_in_range": False
    }
    
    if not coords_data:
        return result
    
    # Look for a line with 2 endpoints
    for item in coords_data:
        coords = item.get("coordinates", [])
        if len(coords) >= 2:
            # Check start and end points
            start = coords[0]
            end = coords[-1]
            
            start_lat, start_lon = start.get("lat", 0), start.get("lon", 0)
            end_lat, end_lon = end.get("lat", 0), end.get("lon", 0)
            
            # Check if this could be our measurement
            start_is_ub = is_near_ulaanbaatar(start_lat, start_lon)
            end_is_coast = is_in_coastline_region(end_lat, end_lon)
            
            # Also check reverse (in case line was drawn coast to UB)
            start_is_coast = is_in_coastline_region(start_lat, start_lon)
            end_is_ub = is_near_ulaanbaatar(end_lat, end_lon)
            
            if (start_is_ub and end_is_coast) or (start_is_coast and end_is_ub):
                result["measurement_found"] = True
                
                if start_is_ub:
                    result["start_coords"] = {"lat": start_lat, "lon": start_lon}
                    result["end_coords"] = {"lat": end_lat, "lon": end_lon}
                    result["start_near_ulaanbaatar"] = True
                    result["end_near_coastline"] = True
                else:
                    result["start_coords"] = {"lat": end_lat, "lon": end_lon}
                    result["end_coords"] = {"lat": start_lat, "lon": start_lon}
                    result["start_near_ulaanbaatar"] = True
                    result["end_near_coastline"] = True
                
                # Calculate distance
                distance = haversine_distance(start_lat, start_lon, end_lat, end_lon)
                result["calculated_distance_km"] = distance
                result["distance_in_range"] = EXPECTED_DISTANCE_MIN <= distance <= EXPECTED_DISTANCE_MAX
                
                return result
    
    # If no perfect match, try to find any line that could be a measurement
    for item in coords_data:
        coords = item.get("coordinates", [])
        if len(coords) >= 2:
            start = coords[0]
            end = coords[-1]
            
            start_lat, start_lon = start.get("lat", 0), start.get("lon", 0)
            end_lat, end_lon = end.get("lat", 0), end.get("lon", 0)
            
            distance = haversine_distance(start_lat, start_lon, end_lat, end_lon)
            
            # If distance is in reasonable range, consider it a candidate
            if 500 <= distance <= 1000:
                result["measurement_found"] = True
                result["start_coords"] = {"lat": start_lat, "lon": start_lon}
                result["end_coords"] = {"lat": end_lat, "lon": end_lon}
                result["start_near_ulaanbaatar"] = is_near_ulaanbaatar(start_lat, start_lon)
                result["end_near_coastline"] = is_in_coastline_region(end_lat, end_lon)
                result["calculated_distance_km"] = distance
                result["distance_in_range"] = EXPECTED_DISTANCE_MIN <= distance <= EXPECTED_DISTANCE_MAX
                return result
    
    return result


# VLM Prompts
TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a distance measurement task in Google Earth.

TASK: Measure the straight-line distance from Ulaanbaatar, Mongolia to the nearest ocean coastline.

The images are sampled chronologically from the agent's interaction (earliest to latest).

For successful completion, the agent should show:
1. Google Earth application open and running
2. Navigation to Mongolia/Ulaanbaatar region (Central Asian steppes, city visible)
3. Use of the Ruler/measurement tool (measurement line visible)
4. A line drawn from Mongolia toward the Chinese coast
5. Distance measurement visible in the interface

Assess:
1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro clearly visible in any frame?
2. MONGOLIA_REGION_SHOWN: Does any frame show Mongolia/Central Asia (landlocked terrain, steppes)?
3. MEASUREMENT_TOOL_USED: Is there evidence of the ruler/measurement tool being used (line drawn on map)?
4. WORKFLOW_PROGRESSION: Do the frames show meaningful state changes (not same screen repeated)?
5. MEASUREMENT_LINE_VISIBLE: Can you see a measurement line connecting two distant points?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "mongolia_region_shown": true/false,
    "measurement_tool_used": true/false,
    "workflow_progression": true/false,
    "measurement_line_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""

FINAL_SCREENSHOT_PROMPT = """You are verifying a screenshot from Google Earth showing a distance measurement task.

TASK: The agent should have measured the distance from Ulaanbaatar, Mongolia to the nearest ocean coastline.

Look at this screenshot and determine:
1. IS_GOOGLE_EARTH: Is this Google Earth (satellite imagery interface)?
2. MEASUREMENT_VISIBLE: Can you see a measurement line drawn on the map?
3. DISTANCE_READOUT: Is there a distance value displayed (should be around 650-750 km)?
4. CORRECT_REGION: Does the view show Central/East Asia (Mongolia to China coast)?
5. MEASUREMENT_QUALITY: Does this look like a legitimate distance measurement between two specific points?

Note: The measurement should span from inland Central Asia (Mongolia region) to an ocean coastline (eastern China coast/Bohai Sea area).

Respond in JSON format:
{
    "is_google_earth": true/false,
    "measurement_visible": true/false,
    "distance_readout_visible": true/false,
    "correct_region": true/false,
    "measurement_quality": "none"/"poor"/"acceptable"/"good",
    "estimated_distance_shown": "number or 'not visible'",
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""


def verify_landlocked_sea_distance(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the landlocked sea distance measurement task.
    
    Uses multiple independent verification signals:
    1. Programmatic: Check exported files, timestamps, coordinates
    2. VLM Trajectory: Verify workflow progression across trajectory frames
    3. VLM Final: Verify measurement visible in final state
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    score = 0
    max_score = 100
    details = {}
    
    # ================================================================
    # LOAD TASK RESULT FROM CONTAINER
    # ================================================================
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        details["result_loaded"] = True
    except Exception as e:
        logger.warning(f"Failed to load task result: {e}")
        details["result_loaded"] = False
        details["load_error"] = str(e)
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    
    # ================================================================
    # CRITERION 1: Screenshot exists (10 points)
    # ================================================================
    screenshot_info = result.get("screenshot", {})
    screenshot_exists = screenshot_info.get("exists", False)
    
    if screenshot_exists:
        score += 10
        feedback_parts.append("✅ Screenshot file exists")
        details["screenshot_exists"] = True
    else:
        feedback_parts.append("❌ Screenshot not found")
        details["screenshot_exists"] = False
    
    # ================================================================
    # CRITERION 2: Screenshot created during task (5 points) - anti-gaming
    # ================================================================
    screenshot_created = screenshot_info.get("created_during_task", False)
    
    if screenshot_created:
        score += 5
        feedback_parts.append("✅ Screenshot created during task")
        details["screenshot_created_during_task"] = True
    else:
        feedback_parts.append("⚠️ Screenshot timestamp issue")
        details["screenshot_created_during_task"] = False
    
    # ================================================================
    # CRITERION 3: Screenshot size reasonable (5 points)
    # ================================================================
    screenshot_size = screenshot_info.get("size_bytes", 0)
    
    if screenshot_size > 50000:  # > 50KB
        score += 5
        feedback_parts.append(f"✅ Screenshot size OK ({screenshot_size/1024:.1f}KB)")
        details["screenshot_size_ok"] = True
    elif screenshot_size > 10000:
        score += 2
        feedback_parts.append(f"⚠️ Screenshot small ({screenshot_size/1024:.1f}KB)")
        details["screenshot_size_ok"] = False
    else:
        feedback_parts.append(f"❌ Screenshot too small or missing ({screenshot_size} bytes)")
        details["screenshot_size_ok"] = False
    
    # ================================================================
    # CRITERION 4: myplaces.kml modified during task (10 points)
    # ================================================================
    myplaces_info = result.get("myplaces", {})
    myplaces_modified = myplaces_info.get("modified_during_task", False)
    
    if myplaces_modified:
        score += 10
        feedback_parts.append("✅ Measurement saved to My Places")
        details["myplaces_modified"] = True
    else:
        feedback_parts.append("⚠️ No changes to My Places")
        details["myplaces_modified"] = False
    
    # ================================================================
    # CRITERION 5-7: Coordinate analysis (35 points total)
    # ================================================================
    coords_data = result.get("coordinates_data", [])
    coord_analysis = analyze_coordinates(coords_data)
    details["coordinate_analysis"] = coord_analysis
    
    # 5a: Measurement found in data (15 points)
    if coord_analysis["measurement_found"]:
        score += 15
        feedback_parts.append("✅ Measurement line found in saved data")
    else:
        feedback_parts.append("⚠️ No measurement line found in KML data")
    
    # 5b: Start point near Ulaanbaatar (10 points)
    if coord_analysis["start_near_ulaanbaatar"]:
        score += 10
        start = coord_analysis.get("start_coords", {})
        feedback_parts.append(f"✅ Start point near Ulaanbaatar ({start.get('lat', 0):.2f}, {start.get('lon', 0):.2f})")
    elif coord_analysis["measurement_found"]:
        feedback_parts.append("⚠️ Start point not clearly at Ulaanbaatar")
    
    # 5c: End point in coastline region (10 points)
    if coord_analysis["end_near_coastline"]:
        score += 10
        end = coord_analysis.get("end_coords", {})
        feedback_parts.append(f"✅ End point in Bohai Sea region ({end.get('lat', 0):.2f}, {end.get('lon', 0):.2f})")
    elif coord_analysis["measurement_found"]:
        feedback_parts.append("⚠️ End point not clearly at coastline")
    
    # Distance check (informational, covered by coordinate checks)
    if coord_analysis["calculated_distance_km"]:
        dist = coord_analysis["calculated_distance_km"]
        if coord_analysis["distance_in_range"]:
            feedback_parts.append(f"✅ Distance {dist:.1f}km is in expected range (650-750km)")
        else:
            feedback_parts.append(f"⚠️ Distance {dist:.1f}km outside expected range (650-750km)")
    
    # ================================================================
    # CRITERION 6: Google Earth was running (5 points)
    # ================================================================
    ge_info = result.get("google_earth", {})
    ge_running = ge_info.get("running", False)
    
    if ge_running:
        score += 5
        feedback_parts.append("✅ Google Earth was running")
        details["google_earth_running"] = True
    else:
        feedback_parts.append("⚠️ Google Earth not detected as running")
        details["google_earth_running"] = False
    
    # ================================================================
    # CRITERION 7: VLM Trajectory Verification (10 points)
    # ================================================================
    vlm_trajectory_score = 0
    
    if query_vlm:
        try:
            # Import trajectory frame helpers
            from gym_anything.vlm import sample_trajectory_frames
            
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            
            if trajectory_frames:
                vlm_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=trajectory_frames
                )
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    details["vlm_trajectory"] = parsed
                    
                    # Score based on criteria met
                    criteria_met = sum([
                        parsed.get("google_earth_visible", False),
                        parsed.get("mongolia_region_shown", False),
                        parsed.get("measurement_tool_used", False),
                        parsed.get("workflow_progression", False),
                        parsed.get("measurement_line_visible", False)
                    ])
                    
                    vlm_trajectory_score = min(10, criteria_met * 2)
                    
                    if criteria_met >= 3:
                        feedback_parts.append(f"✅ VLM trajectory: workflow verified ({criteria_met}/5 criteria)")
                    else:
                        feedback_parts.append(f"⚠️ VLM trajectory: partial workflow ({criteria_met}/5 criteria)")
                else:
                    feedback_parts.append("⚠️ VLM trajectory query failed")
                    details["vlm_trajectory_error"] = vlm_result.get("error", "unknown")
            else:
                feedback_parts.append("⚠️ No trajectory frames available")
        except Exception as e:
            logger.warning(f"VLM trajectory verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM trajectory error: {str(e)[:50]}")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    score += vlm_trajectory_score
    
    # ================================================================
    # CRITERION 8: VLM Final Screenshot Verification (10 points)
    # ================================================================
    vlm_final_score = 0
    
    if query_vlm:
        try:
            from gym_anything.vlm import get_final_screenshot
            
            final_screenshot = get_final_screenshot(traj)
            
            if final_screenshot:
                vlm_result = query_vlm(
                    prompt=FINAL_SCREENSHOT_PROMPT,
                    image=final_screenshot
                )
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    details["vlm_final"] = parsed
                    
                    is_ge = parsed.get("is_google_earth", False)
                    measurement_visible = parsed.get("measurement_visible", False)
                    distance_visible = parsed.get("distance_readout_visible", False)
                    correct_region = parsed.get("correct_region", False)
                    quality = parsed.get("measurement_quality", "none")
                    
                    if is_ge and measurement_visible:
                        vlm_final_score = 6
                        if distance_visible:
                            vlm_final_score += 2
                        if correct_region:
                            vlm_final_score += 2
                        feedback_parts.append(f"✅ VLM final: measurement visible (quality: {quality})")
                    elif is_ge:
                        vlm_final_score = 3
                        feedback_parts.append("⚠️ VLM final: Google Earth but measurement not clear")
                    else:
                        feedback_parts.append("❌ VLM final: Google Earth or measurement not detected")
                else:
                    feedback_parts.append("⚠️ VLM final query failed")
            else:
                feedback_parts.append("⚠️ No final screenshot available")
        except Exception as e:
            logger.warning(f"VLM final verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM final error: {str(e)[:50]}")
    else:
        feedback_parts.append("⚠️ VLM not available for final verification")
    
    score += vlm_final_score
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key criteria: screenshot exists AND (measurement data found OR VLM confirms)
    key_criteria_met = (
        screenshot_exists and 
        (coord_analysis["measurement_found"] or vlm_trajectory_score >= 6 or vlm_final_score >= 6)
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "max_score": max_score,
        "feedback": feedback,
        "details": details
    }