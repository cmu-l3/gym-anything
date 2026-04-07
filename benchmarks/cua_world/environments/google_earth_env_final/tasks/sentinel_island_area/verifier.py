#!/usr/bin/env python3
"""
Verifier for North Sentinel Island Area Measurement task.

MULTI-SIGNAL VERIFICATION STRATEGY:
1. KML file exists and was created during task (20 points)
2. KML contains valid polygon with coordinates (15 points)  
3. Polygon has sufficient vertices for coastline accuracy (15 points)
4. Polygon centroid is near North Sentinel Island (20 points)
5. Polygon name matches expected (10 points)
6. VLM: Trajectory shows navigation and polygon creation (20 points)

Pass threshold: 60 points with file created during task AND location verified
"""

import json
import tempfile
import os
import math
import logging
import re
from typing import Dict, Any, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# KML PARSING UTILITIES
# ================================================================

def parse_kml_coordinates(kml_content: str) -> Tuple[Optional[List[Tuple[float, float]]], Optional[str]]:
    """Parse coordinates from KML file content."""
    try:
        # Find coordinates element (handle with or without namespace)
        coord_match = re.search(r'<coordinates[^>]*>(.*?)</coordinates>', kml_content, re.DOTALL | re.IGNORECASE)
        
        if not coord_match:
            return None, "No coordinates element found in KML"
        
        coords_text = coord_match.group(1).strip()
        coords = []
        
        # Parse coordinate tuples (lon,lat,alt format)
        for coord in coords_text.split():
            coord = coord.strip()
            if not coord:
                continue
            parts = coord.split(',')
            if len(parts) >= 2:
                try:
                    lon = float(parts[0])
                    lat = float(parts[1])
                    coords.append((lat, lon))
                except ValueError:
                    continue
        
        if not coords:
            return None, "No valid coordinates parsed from KML"
            
        return coords, None
    except Exception as e:
        return None, str(e)


def calculate_polygon_centroid(coords: List[Tuple[float, float]]) -> Tuple[Optional[float], Optional[float]]:
    """Calculate centroid of polygon coordinates."""
    if not coords:
        return None, None
    avg_lat = sum(c[0] for c in coords) / len(coords)
    avg_lon = sum(c[1] for c in coords) / len(coords)
    return avg_lat, avg_lon


def calculate_polygon_area_km2(coords: List[Tuple[float, float]]) -> float:
    """Calculate polygon area using Shoelace formula with lat/lon to km conversion."""
    if len(coords) < 3:
        return 0.0
    
    # Close polygon if not closed
    if coords[0] != coords[-1]:
        coords = coords + [coords[0]]
    
    # Use average latitude for lon-to-km conversion
    avg_lat = sum(c[0] for c in coords) / len(coords)
    lat_to_km = 111.0  # km per degree latitude
    lon_to_km = 111.0 * math.cos(math.radians(avg_lat))  # km per degree longitude at this latitude
    
    # Shoelace formula
    n = len(coords)
    area = 0.0
    for i in range(n - 1):
        x1 = coords[i][1] * lon_to_km
        y1 = coords[i][0] * lat_to_km
        x2 = coords[i+1][1] * lon_to_km
        y2 = coords[i+1][0] * lat_to_km
        area += (x1 * y2) - (x2 * y1)
    
    return abs(area) / 2.0


def extract_polygon_name(kml_content: str) -> str:
    """Extract polygon/placemark name from KML."""
    name_match = re.search(r'<name[^>]*>(.*?)</name>', kml_content, re.IGNORECASE)
    if name_match:
        return name_match.group(1).strip()
    return ""


def check_has_polygon_element(kml_content: str) -> bool:
    """Check if KML contains a polygon element."""
    return bool(re.search(r'<Polygon>|<LinearRing>', kml_content, re.IGNORECASE))


# ================================================================
# VLM VERIFICATION
# ================================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are verifying if an agent successfully measured the area of North Sentinel Island in Google Earth.

The images are sampled chronologically from the agent's interaction (earliest to latest).

For successful polygon area measurement, the agent should progress through:
1. Google Earth open - the application interface is visible
2. Navigation to island - view shows a small forested island in ocean (teardrop-shaped)
3. Polygon tool usage - points being placed around an island coastline
4. Polygon completion - a closed polygon shape visible on the island
5. Save/export - a save dialog or confirmation visible

Assess:
1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro interface visible in any frame?
2. ISLAND_NAVIGATION: Is a small island (forested, surrounded by ocean/reef) visible?
3. POLYGON_TOOL_USED: Are polygon points or lines visible being drawn around land?
4. MEANINGFUL_WORKFLOW: Do frames show progression through the task (not same screen)?
5. CORRECT_LOCATION: Does this look like a remote tropical island (Andaman Sea region)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "island_navigation": true/false,
    "polygon_tool_used": true/false,
    "meaningful_workflow": true/false,
    "correct_location": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""


def verify_with_vlm(traj: Dict[str, Any], query_vlm) -> Dict[str, Any]:
    """Verify task using trajectory frames with VLM."""
    if not query_vlm:
        return {"success": False, "error": "VLM query function not available", "score": 0}
    
    # Import trajectory frame sampling utilities
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        # Fallback if import fails
        return {"success": False, "error": "Could not import VLM utilities", "score": 0}
    
    # Sample frames across trajectory (use multiple frames, not just final)
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    
    if final_frame and final_frame not in frames:
        frames.append(final_frame)
    
    if not frames:
        return {"success": False, "error": "No trajectory frames available", "score": 0}
    
    try:
        vlm_result = query_vlm(
            prompt=TRAJECTORY_VERIFICATION_PROMPT,
            images=frames
        )
        
        if not vlm_result.get("success"):
            return {"success": False, "error": vlm_result.get("error", "VLM query failed"), "score": 0}
        
        parsed = vlm_result.get("parsed", {})
        
        # Calculate VLM score based on criteria
        criteria_met = 0
        total_criteria = 5
        
        if parsed.get("google_earth_visible", False):
            criteria_met += 1
        if parsed.get("island_navigation", False):
            criteria_met += 1
        if parsed.get("polygon_tool_used", False):
            criteria_met += 1
        if parsed.get("meaningful_workflow", False):
            criteria_met += 1
        if parsed.get("correct_location", False):
            criteria_met += 1
        
        # Adjust score based on confidence
        confidence = parsed.get("confidence", "low")
        confidence_multiplier = {"high": 1.0, "medium": 0.85, "low": 0.7}.get(confidence, 0.7)
        
        vlm_score = int((criteria_met / total_criteria) * 20 * confidence_multiplier)
        
        return {
            "success": True,
            "score": vlm_score,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "confidence": confidence,
            "parsed": parsed,
            "frame_count": len(frames)
        }
        
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        return {"success": False, "error": str(e), "score": 0}


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_sentinel_island_area(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify North Sentinel Island area measurement task.
    
    Uses multiple independent verification signals to prevent gaming.
    
    Args:
        traj: Trajectory data with frames and episode info
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "❌ Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_lat = metadata.get('expected_latitude', 11.55)
    expected_lon = metadata.get('expected_longitude', 92.24)
    lat_tolerance = metadata.get('lat_tolerance', 0.15)
    lon_tolerance = metadata.get('lon_tolerance', 0.15)
    min_area = metadata.get('expected_area_km2_min', 40)
    max_area = metadata.get('expected_area_km2_max', 100)
    min_vertices = metadata.get('min_vertices', 15)
    expected_name = metadata.get('polygon_name', 'North_Sentinel_Island_Boundary')
    output_path = metadata.get('expected_output_path', '/home/ga/Documents/north_sentinel_boundary.kml')
    
    score = 0
    max_score = 100
    feedback_parts = []
    result_details = {}
    
    # ================================================================
    # STEP 1: Copy and parse task result JSON
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        result_details['task_result'] = result
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": f"❌ Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: KML file exists and was created during task (20 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if output_exists and file_created_during_task:
        score += 20
        feedback_parts.append("✅ KML file exported during task")
    elif output_exists:
        score += 8
        feedback_parts.append("⚠️ KML file exists but may predate task")
    else:
        feedback_parts.append("❌ KML file not found")
        # Early exit - can't verify much without the file
        vlm_result = verify_with_vlm(traj, query_vlm)
        if vlm_result.get('success'):
            score += vlm_result.get('score', 0)
            feedback_parts.append(f"VLM score: {vlm_result.get('score', 0)}/20")
        
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": result_details
        }
    
    # ================================================================
    # STEP 2: Copy and parse KML file
    # ================================================================
    kml_content = ""
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env(output_path, temp_kml.name)
        with open(temp_kml.name, 'r') as f:
            kml_content = f.read()
        result_details['kml_size'] = len(kml_content)
    except Exception as e:
        logger.warning(f"Could not copy KML file: {e}")
        # Try alternate location
        try:
            copy_from_env("/tmp/exported_polygon.kml", temp_kml.name)
            with open(temp_kml.name, 'r') as f:
                kml_content = f.read()
        except:
            feedback_parts.append("⚠️ Could not read KML file content")
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # CRITERION 2: KML contains valid polygon with coordinates (15 points)
    # ================================================================
    has_polygon = check_has_polygon_element(kml_content) if kml_content else False
    coords, coord_error = parse_kml_coordinates(kml_content) if kml_content else (None, "No KML content")
    
    if has_polygon and coords and len(coords) >= 3:
        score += 15
        feedback_parts.append(f"✅ Valid polygon with {len(coords)} coordinates")
        result_details['coordinate_count'] = len(coords)
    elif has_polygon:
        score += 5
        feedback_parts.append(f"⚠️ Polygon element found but coordinates invalid: {coord_error}")
    else:
        feedback_parts.append("❌ No valid polygon in KML")
    
    # ================================================================
    # CRITERION 3: Sufficient vertices for coastline accuracy (15 points)
    # ================================================================
    if coords:
        vertex_count = len(coords)
        if vertex_count >= min_vertices:
            score += 15
            feedback_parts.append(f"✅ Sufficient detail ({vertex_count} vertices)")
        elif vertex_count >= 10:
            score += 10
            feedback_parts.append(f"⚠️ Moderate detail ({vertex_count} vertices, expected ≥{min_vertices})")
        elif vertex_count >= 5:
            score += 5
            feedback_parts.append(f"⚠️ Low detail ({vertex_count} vertices)")
        else:
            feedback_parts.append(f"❌ Insufficient vertices ({vertex_count})")
    
    # ================================================================
    # CRITERION 4: Polygon centroid near North Sentinel Island (20 points)
    # ================================================================
    location_verified = False
    if coords:
        centroid_lat, centroid_lon = calculate_polygon_centroid(coords)
        result_details['centroid'] = {'lat': centroid_lat, 'lon': centroid_lon}
        
        if centroid_lat and centroid_lon:
            lat_ok = abs(centroid_lat - expected_lat) <= lat_tolerance
            lon_ok = abs(centroid_lon - expected_lon) <= lon_tolerance
            
            if lat_ok and lon_ok:
                score += 20
                location_verified = True
                feedback_parts.append(f"✅ Location verified (centroid: {centroid_lat:.3f}°N, {centroid_lon:.3f}°E)")
            elif lat_ok or lon_ok:
                score += 10
                feedback_parts.append(f"⚠️ Partial location match (centroid: {centroid_lat:.3f}°N, {centroid_lon:.3f}°E)")
            else:
                feedback_parts.append(f"❌ Wrong location (centroid: {centroid_lat:.3f}°N, {centroid_lon:.3f}°E, expected ~{expected_lat}°N, {expected_lon}°E)")
        
        # Calculate and validate area
        area_km2 = calculate_polygon_area_km2(coords)
        result_details['area_km2'] = area_km2
        
        if min_area <= area_km2 <= max_area:
            feedback_parts.append(f"✅ Area reasonable ({area_km2:.1f} km²)")
        else:
            feedback_parts.append(f"⚠️ Area outside expected range ({area_km2:.1f} km², expected {min_area}-{max_area} km²)")
    
    # ================================================================
    # CRITERION 5: Polygon name matches expected (10 points)
    # ================================================================
    if kml_content:
        polygon_name = extract_polygon_name(kml_content)
        result_details['polygon_name'] = polygon_name
        
        # Flexible name matching
        name_lower = polygon_name.lower()
        expected_lower = expected_name.lower()
        
        if expected_lower in name_lower or 'sentinel' in name_lower or 'island' in name_lower:
            score += 10
            feedback_parts.append(f"✅ Polygon named: '{polygon_name}'")
        elif polygon_name:
            score += 5
            feedback_parts.append(f"⚠️ Polygon name doesn't match: '{polygon_name}'")
        else:
            feedback_parts.append("❌ No polygon name found")
    
    # ================================================================
    # CRITERION 6: VLM trajectory verification (20 points)
    # ================================================================
    vlm_result = verify_with_vlm(traj, query_vlm)
    result_details['vlm_verification'] = vlm_result
    
    if vlm_result.get('success'):
        vlm_score = vlm_result.get('score', 0)
        score += vlm_score
        criteria_met = vlm_result.get('criteria_met', 0)
        total_criteria = vlm_result.get('total_criteria', 5)
        confidence = vlm_result.get('confidence', 'low')
        feedback_parts.append(f"✅ VLM verification: {criteria_met}/{total_criteria} criteria ({confidence} confidence, +{vlm_score}pts)")
    else:
        feedback_parts.append(f"⚠️ VLM verification unavailable: {vlm_result.get('error', 'unknown')}")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Bonus: Google Earth was running
    ge_running = result.get('google_earth_running', False)
    if ge_running:
        result_details['google_earth_running'] = True
    
    # Key criteria for passing
    key_criteria_met = (
        output_exists and 
        file_created_during_task and 
        (location_verified or (coords and len(coords) >= 5))
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    feedback += f" | Total: {score}/{max_score}"
    
    if passed:
        feedback = "✅ PASSED | " + feedback
    else:
        if not key_criteria_met:
            feedback = "❌ FAILED (key criteria not met) | " + feedback
        else:
            feedback = "❌ FAILED (score too low) | " + feedback
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": result_details
    }


# ================================================================
# STANDALONE TESTING
# ================================================================

if __name__ == "__main__":
    # Test with mock data
    print("North Sentinel Island Area Measurement Verifier")
    print("Run via gym-anything framework for actual verification")