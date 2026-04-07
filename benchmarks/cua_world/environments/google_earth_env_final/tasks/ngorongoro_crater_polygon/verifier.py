#!/usr/bin/env python3
"""
Verifier for Ngorongoro Crater Polygon task.

MULTI-SIGNAL VERIFICATION:
1. KML file exists at expected path (15 points)
2. File was created during task execution (15 points) - anti-gaming
3. Valid KML structure with Polygon element (10 points)
4. Polygon coordinates center on Ngorongoro Crater (20 points)
5. Polygon area is reasonable for crater floor (10 points)
6. Green fill color present (10 points)
7. Fill transparency/opacity set (5 points)
8. Red line color present (5 points)
9. Polygon named correctly (5 points)
10. Sufficient vertices for accuracy (5 points)

Plus VLM trajectory verification for workflow progression.

Pass threshold: 65 points with KML file existing and polygon in correct location.
"""

import json
import tempfile
import os
import re
import math
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# KML PARSING UTILITIES
# ================================================================

def parse_kml_polygon(kml_content: str) -> Tuple[Optional[List[Tuple[float, float]]], Optional[str]]:
    """
    Parse KML content and extract polygon coordinates.
    
    Returns:
        Tuple of (coordinates list, error message or None)
        Coordinates are list of (lat, lon) tuples
    """
    try:
        # Handle KML namespace
        # Remove default namespace for easier parsing
        kml_content_clean = re.sub(r'\sxmlns="[^"]+"', '', kml_content, count=1)
        
        root = ET.fromstring(kml_content_clean)
        
        # Find Polygon element (try various paths)
        polygon = None
        for path in ['.//Polygon', './/Placemark/Polygon', './/Document/Placemark/Polygon']:
            polygon = root.find(path)
            if polygon is not None:
                break
        
        if polygon is None:
            return None, "No Polygon element found in KML"
        
        # Find coordinates element
        coords_elem = polygon.find('.//coordinates')
        if coords_elem is None:
            return None, "No coordinates element found in Polygon"
        
        coords_text = coords_elem.text
        if not coords_text:
            return None, "Empty coordinates element"
        
        coords_text = coords_text.strip()
        coordinates = []
        
        # Parse coordinate triplets (lon,lat,alt or lon,lat)
        for point in coords_text.split():
            point = point.strip()
            if not point:
                continue
            parts = point.split(',')
            if len(parts) >= 2:
                try:
                    lon = float(parts[0])
                    lat = float(parts[1])
                    coordinates.append((lat, lon))
                except ValueError:
                    continue
        
        if len(coordinates) < 3:
            return None, f"Insufficient coordinates ({len(coordinates)})"
        
        return coordinates, None
        
    except ET.ParseError as e:
        return None, f"XML parse error: {e}"
    except Exception as e:
        return None, f"Parse error: {e}"


def calculate_centroid(coords: List[Tuple[float, float]]) -> Tuple[float, float]:
    """Calculate centroid of polygon coordinates."""
    if not coords:
        return 0.0, 0.0
    lat_sum = sum(c[0] for c in coords)
    lon_sum = sum(c[1] for c in coords)
    return lat_sum / len(coords), lon_sum / len(coords)


def calculate_area_km2(coords: List[Tuple[float, float]]) -> float:
    """
    Calculate approximate polygon area in km² using shoelace formula.
    This is an approximation suitable for relatively small polygons.
    """
    if len(coords) < 3:
        return 0.0
    
    # Use shoelace formula in lat/lon space
    n = len(coords)
    area = 0.0
    for i in range(n):
        j = (i + 1) % n
        area += coords[i][1] * coords[j][0]  # lon_i * lat_j
        area -= coords[j][1] * coords[i][0]  # lon_j * lat_i
    area = abs(area) / 2.0
    
    # Convert to km² (approximate at equator, adjusted for latitude)
    lat_center = sum(c[0] for c in coords) / n
    km_per_deg_lat = 111.0  # km per degree latitude
    km_per_deg_lon = 111.0 * math.cos(math.radians(abs(lat_center)))
    
    area_km2 = area * km_per_deg_lat * km_per_deg_lon
    return area_km2


def check_kml_styling(kml_content: str) -> Dict[str, bool]:
    """
    Check polygon styling in KML content.
    
    Returns dict with:
        - has_green_fill
        - has_transparency
        - has_red_line
    """
    content_lower = kml_content.lower()
    results = {
        'has_green_fill': False,
        'has_transparency': False,
        'has_red_line': False
    }
    
    # KML colors are in aabbggrr format (alpha, blue, green, red)
    # Green fill would have high green component
    # Check for various green patterns
    
    # Look for PolyStyle with green color
    # Green in aabbggrr: xx00FFxx or similar
    green_patterns = [
        r'ff00ff00',  # Opaque pure green (aabbggrr)
        r'[0-9a-f]{2}00ff00',  # Any alpha, pure green
        r'[0-9a-f]{2}00[89a-f][0-9a-f]00',  # Greenish colors
        r'7f00ff00',  # 50% transparent green
        r'4c00ff00',  # 30% transparent green
    ]
    
    for pattern in green_patterns:
        if re.search(pattern, content_lower):
            results['has_green_fill'] = True
            break
    
    # Also check for color names or RGB in different formats
    if 'green' in content_lower or '#00ff00' in content_lower:
        results['has_green_fill'] = True
    
    # Check for transparency (alpha < ff in KML color format)
    # KML uses aabbggrr, so first 2 chars are alpha
    color_matches = re.findall(r'<color>([0-9a-f]{8})</color>', content_lower)
    for color in color_matches:
        alpha = color[:2]
        if alpha != 'ff':  # Not fully opaque
            results['has_transparency'] = True
            break
    
    # Also check for fill/outline opacity elements
    if '<fill>0' in content_lower or '<outline>' in content_lower:
        pass  # These don't indicate transparency directly
    
    # Check for red line color
    # Red in aabbggrr: xxxx0000ff or xx0000ff
    red_patterns = [
        r'ff0000ff',  # Opaque pure red (aabbggrr)
        r'[0-9a-f]{2}0000ff',  # Any alpha, pure red
        r'[0-9a-f]{2}00[0-3][0-9a-f]ff',  # Reddish colors
    ]
    
    for pattern in red_patterns:
        if re.search(pattern, content_lower):
            results['has_red_line'] = True
            break
    
    # Also check for color names
    if 'red' in content_lower or '#ff0000' in content_lower:
        results['has_red_line'] = True
    
    return results


def check_polygon_name(kml_content: str) -> bool:
    """Check if polygon is named with 'Ngorongoro'."""
    content_lower = kml_content.lower()
    return 'ngorongoro' in content_lower


# ================================================================
# VLM VERIFICATION
# ================================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a polygon in Google Earth Pro.

The agent's task was to:
1. Navigate to Ngorongoro Crater in Tanzania
2. Create a polygon tracing the crater floor
3. Style it with green fill, red outline, and transparency
4. Save it as a KML file

Look at these screenshots (from earliest to latest) and determine:

1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro visible in any frame?
2. CRATER_VISIBLE: Can you see Ngorongoro Crater (a large circular volcanic crater in Tanzania)?
3. POLYGON_TOOL_USED: Is there evidence the polygon tool was accessed (Add menu, polygon dialog, drawing vertices)?
4. POLYGON_VISIBLE: Can you see a polygon shape being drawn or completed around the crater?
5. STYLING_DIALOG: Is there evidence of accessing styling options (color selection, properties dialog)?
6. SAVE_DIALOG: Is there evidence of saving (Save As dialog, file browser)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "crater_visible": true/false,
    "polygon_tool_used": true/false,
    "polygon_visible": true/false,
    "styling_dialog": true/false,
    "save_dialog": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""


def vlm_verify_trajectory(traj: Dict[str, Any], query_vlm) -> Dict[str, Any]:
    """Use VLM to verify trajectory shows proper workflow."""
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}
    
    try:
        # Import trajectory sampling utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames across the trajectory
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if final and final not in frames:
            frames.append(final)
        
        if not frames:
            return {"success": False, "error": "No trajectory frames available"}
        
        # Query VLM with multiple frames
        result = query_vlm(
            prompt=TRAJECTORY_VERIFICATION_PROMPT,
            images=frames
        )
        
        if not result.get("success"):
            return {"success": False, "error": result.get("error", "VLM query failed")}
        
        parsed = result.get("parsed", {})
        return {"success": True, "parsed": parsed}
        
    except ImportError:
        # Fallback if trajectory sampling not available
        logger.warning("Could not import trajectory sampling utilities")
        return {"success": False, "error": "Trajectory sampling not available"}
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        return {"success": False, "error": str(e)}


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_ngorongoro_crater_polygon(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify Ngorongoro Crater Polygon task completion.
    
    Uses multiple signals:
    1. KML file analysis (existence, structure, coordinates, styling)
    2. Timestamp verification (anti-gaming)
    3. VLM trajectory verification
    
    Args:
        traj: Trajectory data
        env_info: Environment info with copy_from_env function
        task_info: Task metadata
        
    Returns:
        Dict with 'passed', 'score', 'feedback', 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    metadata = task_info.get('metadata', {})
    expected_lat = metadata.get('expected_center_lat', -3.17)
    expected_lon = metadata.get('expected_center_lon', 35.59)
    coord_tolerance = metadata.get('coordinate_tolerance', 0.1)
    expected_area = metadata.get('expected_area_km2', 260)
    area_tolerance = metadata.get('area_tolerance_km2', 100)
    min_vertices = metadata.get('min_vertices', 15)
    
    score = 0
    feedback_parts = []
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
        details['export_result'] = result_data
    except Exception as e:
        logger.warning(f"Could not read task result: {e}")
        details['export_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Copy KML file from container
    # ================================================================
    kml_content = ""
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env("/tmp/ngorongoro_habitat.kml", temp_kml.name)
        with open(temp_kml.name, 'r') as f:
            kml_content = f.read()
        details['kml_file_copied'] = True
        details['kml_size'] = len(kml_content)
    except Exception as e:
        logger.warning(f"Could not copy KML file: {e}")
        details['kml_file_copied'] = False
        details['kml_copy_error'] = str(e)
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # CRITERION 1: KML file exists (15 points)
    # ================================================================
    output_exists = result_data.get('output_exists', False) or len(kml_content) > 0
    
    if output_exists and len(kml_content) > 0:
        score += 15
        feedback_parts.append("✅ KML file exists (+15)")
    elif output_exists:
        score += 5
        feedback_parts.append("⚠️ KML file reported but couldn't read content (+5)")
    else:
        feedback_parts.append("❌ KML file not found (0/15)")
        # Still try VLM verification even without file
    
    # ================================================================
    # CRITERION 2: File created during task (15 points) - ANTI-GAMING
    # ================================================================
    file_created = result_data.get('file_created_during_task', False)
    
    if file_created:
        score += 15
        feedback_parts.append("✅ File created during task execution (+15)")
    else:
        if output_exists:
            feedback_parts.append("⚠️ File exists but creation time suspicious (0/15)")
        else:
            feedback_parts.append("❌ No file creation detected (0/15)")
    
    # ================================================================
    # CRITERION 3: Valid KML structure with Polygon (10 points)
    # ================================================================
    coords = None
    parse_error = None
    
    if kml_content:
        coords, parse_error = parse_kml_polygon(kml_content)
        
        if coords and len(coords) >= 3:
            score += 10
            feedback_parts.append(f"✅ Valid KML with {len(coords)} vertices (+10)")
            details['vertex_count'] = len(coords)
        else:
            feedback_parts.append(f"❌ Invalid KML structure: {parse_error} (0/10)")
            details['parse_error'] = parse_error
    else:
        feedback_parts.append("❌ No KML content to parse (0/10)")
    
    # ================================================================
    # CRITERION 4: Polygon in correct location (20 points)
    # ================================================================
    if coords:
        centroid_lat, centroid_lon = calculate_centroid(coords)
        lat_diff = abs(centroid_lat - expected_lat)
        lon_diff = abs(centroid_lon - expected_lon)
        
        details['centroid'] = {'lat': centroid_lat, 'lon': centroid_lon}
        details['expected'] = {'lat': expected_lat, 'lon': expected_lon}
        details['coordinate_diff'] = {'lat': lat_diff, 'lon': lon_diff}
        
        if lat_diff <= coord_tolerance and lon_diff <= coord_tolerance:
            score += 20
            feedback_parts.append(f"✅ Polygon centered on Ngorongoro ({centroid_lat:.3f}°, {centroid_lon:.3f}°) (+20)")
        elif lat_diff <= coord_tolerance * 2 and lon_diff <= coord_tolerance * 2:
            score += 10
            feedback_parts.append(f"⚠️ Polygon near Ngorongoro but offset ({centroid_lat:.3f}°, {centroid_lon:.3f}°) (+10)")
        else:
            feedback_parts.append(f"❌ Polygon not at Ngorongoro (centroid: {centroid_lat:.3f}°, {centroid_lon:.3f}°) (0/20)")
    else:
        feedback_parts.append("❌ Cannot verify location - no valid coordinates (0/20)")
    
    # ================================================================
    # CRITERION 5: Polygon area reasonable (10 points)
    # ================================================================
    if coords:
        area_km2 = calculate_area_km2(coords)
        details['calculated_area_km2'] = area_km2
        
        if abs(area_km2 - expected_area) <= area_tolerance:
            score += 10
            feedback_parts.append(f"✅ Polygon area ~{area_km2:.0f} km² (+10)")
        elif area_km2 > 50 and area_km2 < 500:  # Reasonable range
            score += 5
            feedback_parts.append(f"⚠️ Polygon area {area_km2:.0f} km² (expected ~{expected_area}) (+5)")
        else:
            feedback_parts.append(f"❌ Polygon area {area_km2:.0f} km² unreasonable (0/10)")
    else:
        feedback_parts.append("❌ Cannot calculate area - no valid coordinates (0/10)")
    
    # ================================================================
    # CRITERIA 6-8: Styling (20 points total)
    # ================================================================
    if kml_content:
        styling = check_kml_styling(kml_content)
        details['styling'] = styling
        
        # Green fill (10 points)
        if styling['has_green_fill']:
            score += 10
            feedback_parts.append("✅ Green fill color detected (+10)")
        else:
            feedback_parts.append("❌ Green fill color not detected (0/10)")
        
        # Transparency (5 points)
        if styling['has_transparency']:
            score += 5
            feedback_parts.append("✅ Fill transparency detected (+5)")
        else:
            feedback_parts.append("❌ Fill transparency not detected (0/5)")
        
        # Red line (5 points)
        if styling['has_red_line']:
            score += 5
            feedback_parts.append("✅ Red line color detected (+5)")
        else:
            feedback_parts.append("❌ Red line color not detected (0/5)")
    else:
        feedback_parts.append("❌ Cannot check styling - no KML content (0/20)")
    
    # ================================================================
    # CRITERION 9: Polygon named correctly (5 points)
    # ================================================================
    if kml_content:
        if check_polygon_name(kml_content):
            score += 5
            feedback_parts.append("✅ Polygon named with 'Ngorongoro' (+5)")
        else:
            feedback_parts.append("❌ Polygon name missing 'Ngorongoro' (0/5)")
    else:
        feedback_parts.append("❌ Cannot check name - no KML content (0/5)")
    
    # ================================================================
    # CRITERION 10: Sufficient vertices (5 points)
    # ================================================================
    if coords:
        if len(coords) >= min_vertices:
            score += 5
            feedback_parts.append(f"✅ Sufficient vertices ({len(coords)} >= {min_vertices}) (+5)")
        else:
            feedback_parts.append(f"❌ Too few vertices ({len(coords)} < {min_vertices}) (0/5)")
    else:
        feedback_parts.append("❌ Cannot count vertices - no valid coordinates (0/5)")
    
    # ================================================================
    # VLM TRAJECTORY VERIFICATION (bonus validation, not scored)
    # ================================================================
    vlm_result = vlm_verify_trajectory(traj, query_vlm)
    details['vlm_verification'] = vlm_result
    
    if vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        vlm_checks = [
            parsed.get('google_earth_visible', False),
            parsed.get('crater_visible', False),
            parsed.get('polygon_tool_used', False),
            parsed.get('polygon_visible', False),
        ]
        vlm_passed = sum(vlm_checks) >= 2
        
        if vlm_passed:
            feedback_parts.append(f"✅ VLM: Workflow evidence detected ({sum(vlm_checks)}/4 indicators)")
        else:
            feedback_parts.append(f"⚠️ VLM: Limited workflow evidence ({sum(vlm_checks)}/4 indicators)")
        
        details['vlm_indicators'] = {
            'google_earth_visible': parsed.get('google_earth_visible'),
            'crater_visible': parsed.get('crater_visible'),
            'polygon_tool_used': parsed.get('polygon_tool_used'),
            'polygon_visible': parsed.get('polygon_visible'),
            'confidence': parsed.get('confidence'),
        }
    else:
        feedback_parts.append(f"⚠️ VLM verification unavailable: {vlm_result.get('error', 'unknown')}")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Key criteria for passing:
    # - File exists AND was created during task
    # - Polygon is in correct location (at least partial credit)
    location_verified = coords is not None and details.get('coordinate_diff', {}).get('lat', 999) <= coord_tolerance * 2
    
    key_criteria_met = (
        output_exists and
        file_created and
        location_verified
    )
    
    passed = score >= 65 and key_criteria_met
    
    # Adjust feedback based on result
    if passed:
        feedback_summary = f"✅ PASSED ({score}/100 points)"
    elif score >= 65:
        feedback_summary = f"❌ FAILED - Score sufficient ({score}/100) but key criteria not met"
    else:
        feedback_summary = f"❌ FAILED ({score}/100 points, need 65+)"
    
    feedback = feedback_summary + "\n" + "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }