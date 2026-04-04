#!/usr/bin/env python3
"""
Verifier for Alcatraz Boundary Export task.

MULTI-SIGNAL VERIFICATION:
1. KML file exists at expected path (10 points)
2. File was created during task (10 points) - anti-gaming
3. Valid KML/XML format (10 points)
4. Contains Polygon element with coordinates (10 points)
5. Centroid within tolerance of Alcatraz (20 points)
6. All vertices in bounding box (15 points)
7. Minimum vertex count for coastline (10 points)
8. Area within expected range (10 points)
9. Correct naming (5 points)

VLM TRAJECTORY VERIFICATION:
- Uses trajectory frames to verify polygon creation workflow

Pass threshold: 70 points AND centroid_valid
"""

import json
import tempfile
import os
import math
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_kml_coordinates(kml_content):
    """Parse coordinates from KML content string."""
    try:
        root = ET.fromstring(kml_content)
        
        # Try various paths to find coordinates (with and without namespace)
        coords_elem = None
        for path in [
            './/{http://www.opengis.net/kml/2.2}coordinates',
            './/coordinates'
        ]:
            coords_elem = root.find(path)
            if coords_elem is not None and coords_elem.text:
                break
        
        if coords_elem is None or not coords_elem.text:
            return None, "No coordinates element found"
        
        coords_text = coords_elem.text.strip()
        coordinates = []
        
        for coord_str in coords_text.split():
            parts = coord_str.strip().split(',')
            if len(parts) >= 2:
                try:
                    lon = float(parts[0])
                    lat = float(parts[1])
                    coordinates.append((lat, lon))
                except ValueError:
                    continue
        
        return coordinates, None
        
    except ET.ParseError as e:
        return None, f"XML parse error: {e}"
    except Exception as e:
        return None, f"Error parsing KML: {e}"


def calculate_centroid(coordinates):
    """Calculate centroid of polygon."""
    if not coordinates:
        return None, None
    
    lat_sum = sum(c[0] for c in coordinates)
    lon_sum = sum(c[1] for c in coordinates)
    n = len(coordinates)
    
    return lat_sum / n, lon_sum / n


def calculate_polygon_area(coordinates):
    """Calculate area of polygon in hectares using Shoelace formula."""
    if len(coordinates) < 3:
        return 0
    
    # Convert to approximate meters at Alcatraz latitude (~37.8°N)
    # 1° lat ≈ 111,000m, 1° lon ≈ 87,800m at this latitude
    lat_to_m = 111000
    lon_to_m = 87800
    
    # Use first point as origin
    origin_lat, origin_lon = coordinates[0]
    
    # Convert to local coordinates in meters
    local_coords = []
    for lat, lon in coordinates:
        x = (lon - origin_lon) * lon_to_m
        y = (lat - origin_lat) * lat_to_m
        local_coords.append((x, y))
    
    # Shoelace formula for polygon area
    n = len(local_coords)
    area = 0
    for i in range(n):
        j = (i + 1) % n
        area += local_coords[i][0] * local_coords[j][1]
        area -= local_coords[j][0] * local_coords[i][1]
    
    area = abs(area) / 2.0
    
    # Convert to hectares (1 hectare = 10,000 m²)
    return area / 10000


def check_bounding_box(coordinates, bbox):
    """Check if all coordinates are within bounding box."""
    for lat, lon in coordinates:
        if lat < bbox['south'] or lat > bbox['north']:
            return False
        if lon < bbox['west'] or lon > bbox['east']:
            return False
    return True


# VLM Prompts
TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a polygon boundary in Google Earth Pro.

The task is to:
1. Navigate to Alcatraz Island in San Francisco Bay
2. Create a polygon tracing the island's coastline
3. Name it "Alcatraz_Boundary"
4. Export as KML file

Analyze these screenshots (in chronological order) and determine:

1. NAVIGATION: Did the agent navigate to San Francisco Bay / Alcatraz Island area?
   - Look for water (bay), island landmass, urban San Francisco in background

2. POLYGON_TOOL: Was the polygon creation tool activated?
   - Look for Add Polygon dialog, polygon drawing mode, vertices being placed

3. COASTLINE_TRACING: Were multiple points placed around an island coastline?
   - Should see irregular polygon shape following shoreline, not a simple rectangle

4. NAMING_DIALOG: Was a properties/naming dialog shown?
   - Look for dialog with name field containing "Alcatraz" or similar

5. EXPORT_WORKFLOW: Was Save Place As dialog used?
   - Look for file save dialog, KML format selection, Documents folder

Respond in JSON format:
{
    "navigation_to_alcatraz": true/false,
    "polygon_tool_used": true/false,
    "coastline_traced": true/false,
    "naming_dialog_shown": true/false,
    "export_workflow_visible": true/false,
    "stages_observed": ["list what you see"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe the workflow progression"
}
"""

FINAL_STATE_PROMPT = """Analyze this Google Earth Pro screenshot to verify the Alcatraz boundary task completion.

Look for evidence of:
1. Is this Google Earth Pro showing San Francisco Bay area?
2. Is Alcatraz Island visible (small island in the bay)?
3. Is there a polygon outline visible on the island?
4. Is there a My Places panel showing a saved placemark?
5. Any indication of successful KML export (save dialog, confirmation)?

Respond in JSON:
{
    "google_earth_visible": true/false,
    "alcatraz_area_shown": true/false,
    "polygon_visible": true/false,
    "placemark_in_sidebar": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "what you observe"
}
"""


def verify_alcatraz_boundary_export(traj, env_info, task_info):
    """
    Verify that Alcatraz Island boundary was created and exported as KML.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_path', '/home/ga/Documents/alcatraz_boundary.kml')
    target = metadata.get('target_location', {})
    target_lat = target.get('latitude', 37.8267)
    target_lon = target.get('longitude', -122.4230)
    bbox = target.get('bounding_box', {
        'north': 37.8295, 'south': 37.8240,
        'east': -122.4180, 'west': -122.4280
    })
    min_area = metadata.get('expected_area_hectares', {}).get('min', 6)
    max_area = metadata.get('expected_area_hectares', {}).get('max', 15)
    min_vertices = metadata.get('minimum_vertices', 8)
    
    feedback_parts = []
    score = 0
    max_score = 100
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    details['export_result'] = result
    
    # ================================================================
    # CRITERION 1: Output file exists (10 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("✅ KML file exists")
        details['file_exists'] = True
    else:
        feedback_parts.append("❌ KML file NOT found")
        details['file_exists'] = False
        # Can't continue without the file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task (10 points) - ANTI-GAMING
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task")
        details['timestamp_valid'] = True
    else:
        feedback_parts.append("⚠️ File may have existed before task")
        details['timestamp_valid'] = False
    
    # ================================================================
    # CRITERION 3: Valid KML format (10 points)
    # ================================================================
    kml_valid = result.get('kml_valid', False)
    
    if kml_valid:
        score += 10
        feedback_parts.append("✅ Valid KML format")
        details['kml_valid'] = True
    else:
        feedback_parts.append("❌ Invalid KML format")
        details['kml_valid'] = False
    
    # ================================================================
    # CRITERION 4: Contains Polygon with coordinates (10 points)
    # ================================================================
    kml_has_polygon = result.get('kml_has_polygon', False)
    kml_coord_count = result.get('kml_coord_count', 0)
    
    if kml_has_polygon and kml_coord_count >= 3:
        score += 10
        feedback_parts.append(f"✅ Polygon with {kml_coord_count} coordinates")
        details['has_polygon'] = True
    else:
        feedback_parts.append("❌ No valid polygon found")
        details['has_polygon'] = False
    
    # ================================================================
    # Parse coordinates for detailed verification
    # ================================================================
    kml_coordinates_str = result.get('kml_coordinates', '')
    coordinates = []
    
    if kml_coordinates_str:
        for coord_str in kml_coordinates_str.split():
            parts = coord_str.strip().split(',')
            if len(parts) >= 2:
                try:
                    lon = float(parts[0])
                    lat = float(parts[1])
                    coordinates.append((lat, lon))
                except ValueError:
                    continue
    
    details['parsed_coordinates'] = len(coordinates)
    
    # ================================================================
    # CRITERION 5: Centroid within tolerance (20 points) - KEY CRITERION
    # ================================================================
    centroid_valid = False
    
    if len(coordinates) >= 3:
        centroid_lat, centroid_lon = calculate_centroid(coordinates)
        details['centroid'] = {'lat': centroid_lat, 'lon': centroid_lon}
        
        lat_diff = abs(centroid_lat - target_lat)
        lon_diff = abs(centroid_lon - target_lon)
        tolerance = 0.005  # ~500m
        
        details['centroid_diff'] = {'lat': lat_diff, 'lon': lon_diff}
        
        if lat_diff <= tolerance and lon_diff <= tolerance:
            score += 20
            feedback_parts.append(f"✅ Centroid at Alcatraz ({centroid_lat:.4f}, {centroid_lon:.4f})")
            centroid_valid = True
            details['centroid_valid'] = True
        else:
            feedback_parts.append(f"❌ Centroid not at Alcatraz ({centroid_lat:.4f}, {centroid_lon:.4f})")
            details['centroid_valid'] = False
    else:
        feedback_parts.append("❌ Not enough coordinates for centroid")
        details['centroid_valid'] = False
    
    # ================================================================
    # CRITERION 6: All vertices in bounding box (15 points)
    # ================================================================
    if len(coordinates) >= 3:
        bbox_valid = check_bounding_box(coordinates, bbox)
        
        if bbox_valid:
            score += 15
            feedback_parts.append("✅ All vertices within Alcatraz bounds")
            details['bbox_valid'] = True
        else:
            feedback_parts.append("⚠️ Some vertices outside Alcatraz bounds")
            details['bbox_valid'] = False
    else:
        details['bbox_valid'] = False
    
    # ================================================================
    # CRITERION 7: Minimum vertex count (10 points)
    # ================================================================
    vertex_count = len(coordinates)
    
    if vertex_count >= min_vertices:
        score += 10
        feedback_parts.append(f"✅ Sufficient vertices ({vertex_count} >= {min_vertices})")
        details['vertex_count_valid'] = True
    elif vertex_count >= 4:
        score += 5
        feedback_parts.append(f"⚠️ Few vertices ({vertex_count}, need {min_vertices}+)")
        details['vertex_count_valid'] = False
    else:
        feedback_parts.append(f"❌ Insufficient vertices ({vertex_count})")
        details['vertex_count_valid'] = False
    
    # ================================================================
    # CRITERION 8: Area within expected range (10 points)
    # ================================================================
    if len(coordinates) >= 3:
        area = calculate_polygon_area(coordinates)
        details['calculated_area_hectares'] = round(area, 2)
        
        if min_area <= area <= max_area:
            score += 10
            feedback_parts.append(f"✅ Area {area:.2f} ha (expected {min_area}-{max_area})")
            details['area_valid'] = True
        elif area > 0:
            score += 3
            feedback_parts.append(f"⚠️ Area {area:.2f} ha outside range [{min_area}-{max_area}]")
            details['area_valid'] = False
        else:
            feedback_parts.append("❌ Could not calculate area")
            details['area_valid'] = False
    else:
        details['area_valid'] = False
    
    # ================================================================
    # CRITERION 9: Correct naming (5 points)
    # ================================================================
    placemark_name = result.get('kml_placemark_name', '')
    details['placemark_name'] = placemark_name
    
    if placemark_name and 'alcatraz' in placemark_name.lower():
        score += 5
        feedback_parts.append(f"✅ Named correctly: '{placemark_name}'")
        details['naming_valid'] = True
    elif placemark_name:
        score += 2
        feedback_parts.append(f"⚠️ Name '{placemark_name}' doesn't contain 'Alcatraz'")
        details['naming_valid'] = False
    else:
        feedback_parts.append("❌ No placemark name found")
        details['naming_valid'] = False
    
    # ================================================================
    # VLM TRAJECTORY VERIFICATION (bonus validation)
    # ================================================================
    vlm_score = 0
    
    if query_vlm:
        try:
            # Import trajectory sampling utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames for process verification
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            if trajectory_frames:
                # Verify workflow through trajectory
                traj_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=trajectory_frames
                )
                
                if traj_result.get('success'):
                    parsed = traj_result.get('parsed', {})
                    details['vlm_trajectory'] = parsed
                    
                    # Count positive signals
                    traj_signals = sum([
                        parsed.get('navigation_to_alcatraz', False),
                        parsed.get('polygon_tool_used', False),
                        parsed.get('coastline_traced', False),
                        parsed.get('naming_dialog_shown', False),
                        parsed.get('export_workflow_visible', False)
                    ])
                    
                    if traj_signals >= 3:
                        vlm_score = 10
                        feedback_parts.append(f"✅ VLM: Workflow verified ({traj_signals}/5 stages)")
                    elif traj_signals >= 1:
                        vlm_score = 5
                        feedback_parts.append(f"⚠️ VLM: Partial workflow ({traj_signals}/5 stages)")
            
            if final_screenshot:
                # Verify final state
                final_result = query_vlm(
                    prompt=FINAL_STATE_PROMPT,
                    image=final_screenshot
                )
                
                if final_result.get('success'):
                    parsed = final_result.get('parsed', {})
                    details['vlm_final'] = parsed
                    
                    if parsed.get('polygon_visible') or parsed.get('alcatraz_area_shown'):
                        vlm_score = min(vlm_score + 5, 10)
                        
        except ImportError:
            logger.warning("VLM utilities not available")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
    
    details['vlm_bonus'] = vlm_score
    
    # ================================================================
    # Final scoring and pass/fail determination
    # ================================================================
    # VLM is bonus, not required for passing
    final_score = min(score + vlm_score, 100)
    
    # Must meet key criteria to pass:
    # - Score >= 70
    # - Centroid must be valid (proves it's actually Alcatraz)
    passed = final_score >= 70 and centroid_valid
    
    details['programmatic_score'] = score
    details['final_score'] = final_score
    details['centroid_criterion'] = centroid_valid
    
    if passed:
        feedback_parts.insert(0, "🎉 TASK PASSED")
    else:
        if not centroid_valid:
            feedback_parts.insert(0, "❌ FAILED: Polygon not at Alcatraz location")
        else:
            feedback_parts.insert(0, f"❌ FAILED: Score {final_score} < 70")
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }