#!/usr/bin/env python3
"""
Verifier for Barcelona Eixample Block Measurement task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. KML file exists at expected path (10 points)
2. File was created/modified during task - anti-gaming (10 points)
3. Valid KML structure with polygon element (10 points)
4. Polygon coordinates are in Barcelona metro area (15 points)
5. Polygon coordinates are in Eixample district (15 points)
6. Polygon centroid near target block location (15 points)
7. Polygon area matches expected Cerdà block size (15 points)
8. Polygon has sufficient vertices for chamfered corners (10 points)

VLM verification on trajectory frames provides additional confidence.

Pass threshold: 70 points minimum with file existence and correct city as mandatory.
"""

import json
import tempfile
import os
import math
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in meters."""
    R = 6371000  # Earth's radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    
    a = math.sin(delta_phi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def calculate_polygon_area(coords):
    """
    Calculate approximate area of polygon using shoelace formula with geodesic correction.
    coords: list of (lon, lat) tuples
    Returns area in square meters.
    """
    if len(coords) < 3:
        return 0
    
    # Calculate centroid for local projection
    center_lat = sum(c[1] for c in coords) / len(coords)
    center_lon = sum(c[0] for c in coords) / len(coords)
    
    # Approximate conversion factors at this latitude
    lat_to_m = 111320  # meters per degree latitude
    lon_to_m = 111320 * math.cos(math.radians(center_lat))  # meters per degree longitude
    
    # Convert coordinates to local meters
    local_coords = []
    for lon, lat in coords:
        x = (lon - center_lon) * lon_to_m
        y = (lat - center_lat) * lat_to_m
        local_coords.append((x, y))
    
    # Shoelace formula
    n = len(local_coords)
    area = 0
    for i in range(n):
        j = (i + 1) % n
        area += local_coords[i][0] * local_coords[j][1]
        area -= local_coords[j][0] * local_coords[i][1]
    
    return abs(area) / 2


def parse_kml_polygon(kml_content):
    """
    Parse KML content and extract polygon coordinates.
    Returns (coords, error) where coords is list of (lon, lat) tuples.
    """
    try:
        root = ET.fromstring(kml_content)
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        
        # Try with namespace first
        coords_elem = root.find('.//{http://www.opengis.net/kml/2.2}coordinates')
        if coords_elem is None:
            # Try without namespace
            coords_elem = root.find('.//coordinates')
        
        if coords_elem is None or not coords_elem.text:
            return None, "No coordinates element found in KML"
        
        coords_text = coords_elem.text.strip()
        coords = []
        for point in coords_text.split():
            parts = point.split(',')
            if len(parts) >= 2:
                try:
                    lon = float(parts[0])
                    lat = float(parts[1])
                    coords.append((lon, lat))
                except ValueError:
                    continue
        
        if len(coords) < 3:
            return None, f"Insufficient coordinates for polygon: {len(coords)}"
        
        return coords, None
        
    except ET.ParseError as e:
        return None, f"XML parse error: {e}"
    except Exception as e:
        return None, f"Error parsing KML: {e}"


# VLM prompts for trajectory verification
TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a geographic task in Google Earth.

TASK: Navigate to Barcelona's Eixample district and create a polygon tracing a city block.

The images are sampled chronologically from the agent's interaction (earliest to latest).

For successful completion, the agent should progress through:
1. Google Earth is open - the application interface is visible
2. Navigation to Barcelona - urban area with distinctive grid pattern visible
3. Zoom to Eixample district - octagonal-cornered block grid visible
4. Polygon creation - drawing tool active or polygon visible on the map
5. Polygon traced - a polygon shape visible on a city block

Assess:
1. GOOGLE_EARTH_VISIBLE: Is Google Earth clearly visible in the screenshots?
2. BARCELONA_NAVIGATION: Did the agent navigate to Barcelona (Mediterranean coastal city, distinctive grid)?
3. EIXAMPLE_GRID_VISIBLE: Can you see the famous octagonal-cornered Eixample grid pattern?
4. POLYGON_CREATION: Is there evidence of polygon creation (drawing mode or polygon shape)?
5. MEANINGFUL_PROGRESSION: Do the frames show actual navigation progress (not static)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "barcelona_navigation": true/false,
    "eixample_grid_visible": true/false,
    "polygon_creation": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see in the progression"
}
"""


def verify_barcelona_block_measurement(traj, env_info, task_info):
    """
    Verify that the Barcelona block polygon was created correctly.
    
    Uses multi-signal verification:
    - Programmatic checks on KML file content
    - Trajectory-based VLM verification
    - Timestamp anti-gaming checks
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    metadata = task_info.get('metadata', {})
    
    # Expected values from metadata
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/barcelona_block.kml')
    target_lat = metadata.get('target_latitude', 41.3895)
    target_lon = metadata.get('target_longitude', 2.1575)
    eixample_lat_min = metadata.get('eixample_lat_min', 41.380)
    eixample_lat_max = metadata.get('eixample_lat_max', 41.400)
    eixample_lon_min = metadata.get('eixample_lon_min', 2.140)
    eixample_lon_max = metadata.get('eixample_lon_max', 2.180)
    barcelona_lat_min = metadata.get('barcelona_lat_min', 41.30)
    barcelona_lat_max = metadata.get('barcelona_lat_max', 41.50)
    barcelona_lon_min = metadata.get('barcelona_lon_min', 2.00)
    barcelona_lon_max = metadata.get('barcelona_lon_max', 2.30)
    area_min = metadata.get('expected_area_min', 10000)
    area_max = metadata.get('expected_area_max', 16000)
    min_vertices = metadata.get('min_vertices', 8)
    block_tolerance_m = metadata.get('block_tolerance_m', 300)
    
    feedback_parts = []
    score = 0
    max_score = 100
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['export_result'] = result_data
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
        details['export_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: KML file exists (10 points)
    # ================================================================
    kml_content = None
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        # Try primary path
        copy_from_env("/home/ga/Documents/barcelona_block.kml", temp_kml.name)
        with open(temp_kml.name, 'r') as f:
            kml_content = f.read()
        score += 10
        feedback_parts.append("✅ KML file exists")
        details['kml_found'] = True
    except Exception as e:
        # Try alternate path in /tmp
        try:
            copy_from_env("/tmp/barcelona_block.kml", temp_kml.name)
            with open(temp_kml.name, 'r') as f:
                kml_content = f.read()
            score += 10
            feedback_parts.append("✅ KML file exists (alternate path)")
            details['kml_found'] = True
        except:
            feedback_parts.append("❌ KML file NOT found")
            details['kml_found'] = False
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # If no KML, try trajectory verification and return early
    if not kml_content:
        # Attempt VLM trajectory verification for partial credit
        vlm_score = 0
        if query_vlm and traj:
            try:
                from gym_anything.vlm import sample_trajectory_frames
                frames = sample_trajectory_frames(traj, n=5)
                if frames:
                    vlm_result = query_vlm(
                        prompt=TRAJECTORY_VERIFICATION_PROMPT,
                        images=frames
                    )
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        if parsed.get('google_earth_visible'):
                            vlm_score += 5
                        if parsed.get('barcelona_navigation'):
                            vlm_score += 5
                        if parsed.get('eixample_grid_visible'):
                            vlm_score += 5
                        if parsed.get('polygon_creation'):
                            vlm_score += 5
                        feedback_parts.append(f"VLM trajectory: +{vlm_score} points")
                        details['vlm_result'] = parsed
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
        
        return {
            "passed": False,
            "score": score + vlm_score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File was created during task (10 points) - anti-gaming
    # ================================================================
    file_created = result_data.get('file_created_during_task', False)
    if file_created:
        score += 10
        feedback_parts.append("✅ File created during task")
        details['timestamp_valid'] = True
    else:
        # Check if file was at least modified
        task_start = result_data.get('task_start', 0)
        output_mtime = result_data.get('output_mtime', 0)
        if output_mtime > task_start:
            score += 7
            feedback_parts.append("✅ File modified during task")
            details['timestamp_valid'] = True
        else:
            feedback_parts.append("⚠️ File may predate task")
            details['timestamp_valid'] = False
    
    # ================================================================
    # CRITERION 3: Valid KML structure with polygon (10 points)
    # ================================================================
    coords, parse_error = parse_kml_polygon(kml_content)
    
    if coords:
        score += 10
        feedback_parts.append(f"✅ Valid KML with {len(coords)} vertices")
        details['kml_valid'] = True
        details['vertex_count'] = len(coords)
    else:
        feedback_parts.append(f"❌ Invalid KML: {parse_error}")
        details['kml_valid'] = False
        details['parse_error'] = parse_error
        
        # Without valid coordinates, can't do remaining checks
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # Calculate centroid
    centroid_lon = sum(c[0] for c in coords) / len(coords)
    centroid_lat = sum(c[1] for c in coords) / len(coords)
    details['centroid'] = {'lat': centroid_lat, 'lon': centroid_lon}
    
    # ================================================================
    # CRITERION 4: Coordinates in Barcelona metro area (15 points)
    # ================================================================
    in_barcelona = (barcelona_lat_min < centroid_lat < barcelona_lat_max and
                    barcelona_lon_min < centroid_lon < barcelona_lon_max)
    
    if in_barcelona:
        score += 15
        feedback_parts.append("✅ Location is in Barcelona")
        details['in_barcelona'] = True
    else:
        feedback_parts.append(f"❌ Not in Barcelona ({centroid_lat:.4f}, {centroid_lon:.4f})")
        details['in_barcelona'] = False
    
    # ================================================================
    # CRITERION 5: Coordinates in Eixample district (15 points)
    # ================================================================
    in_eixample = (eixample_lat_min < centroid_lat < eixample_lat_max and
                   eixample_lon_min < centroid_lon < eixample_lon_max)
    
    if in_eixample:
        score += 15
        feedback_parts.append("✅ Location is in Eixample district")
        details['in_eixample'] = True
    else:
        feedback_parts.append("⚠️ Not in Eixample district bounds")
        details['in_eixample'] = False
    
    # ================================================================
    # CRITERION 6: Centroid near target block (15 points)
    # ================================================================
    distance_to_target = haversine_distance(centroid_lat, centroid_lon, target_lat, target_lon)
    details['distance_to_target_m'] = round(distance_to_target, 1)
    
    if distance_to_target <= block_tolerance_m:
        score += 15
        feedback_parts.append(f"✅ Near target block ({distance_to_target:.0f}m)")
        details['correct_block'] = True
    elif distance_to_target <= block_tolerance_m * 2:
        score += 8
        feedback_parts.append(f"⚠️ Somewhat near target ({distance_to_target:.0f}m)")
        details['correct_block'] = False
    else:
        feedback_parts.append(f"❌ Far from target block ({distance_to_target:.0f}m)")
        details['correct_block'] = False
    
    # ================================================================
    # CRITERION 7: Area matches expected Cerdà block size (15 points)
    # ================================================================
    polygon_area = calculate_polygon_area(coords)
    details['polygon_area_sqm'] = round(polygon_area, 1)
    
    if area_min <= polygon_area <= area_max:
        score += 15
        feedback_parts.append(f"✅ Area correct ({polygon_area:.0f} sq m)")
        details['area_correct'] = True
    elif area_min * 0.5 <= polygon_area <= area_max * 2:
        score += 7
        feedback_parts.append(f"⚠️ Area somewhat off ({polygon_area:.0f} sq m)")
        details['area_correct'] = False
    else:
        feedback_parts.append(f"❌ Area incorrect ({polygon_area:.0f} sq m)")
        details['area_correct'] = False
    
    # ================================================================
    # CRITERION 8: Polygon complexity - chamfered corners (10 points)
    # ================================================================
    if len(coords) >= min_vertices:
        score += 10
        feedback_parts.append(f"✅ Polygon has chamfered corners ({len(coords)} vertices)")
        details['has_chamfered_corners'] = True
    elif len(coords) >= 4:
        score += 5
        feedback_parts.append(f"⚠️ Simple polygon ({len(coords)} vertices, expected {min_vertices}+)")
        details['has_chamfered_corners'] = False
    else:
        feedback_parts.append(f"❌ Too few vertices ({len(coords)})")
        details['has_chamfered_corners'] = False
    
    # ================================================================
    # VLM TRAJECTORY VERIFICATION (bonus confidence, not scored separately)
    # ================================================================
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                vlm_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=frames
                )
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_trajectory'] = parsed
                    
                    # Log VLM observations
                    if parsed.get('meaningful_progression'):
                        feedback_parts.append("✅ VLM: Navigation progression confirmed")
                    if parsed.get('eixample_grid_visible'):
                        feedback_parts.append("✅ VLM: Eixample grid visible")
        except Exception as e:
            logger.warning(f"VLM trajectory verification failed: {e}")
            details['vlm_error'] = str(e)
    
    # ================================================================
    # FINAL DETERMINATION
    # ================================================================
    # Mandatory criteria: file exists AND in Barcelona
    mandatory_met = details.get('kml_found', False) and details.get('in_barcelona', False)
    passed = score >= 70 and mandatory_met
    
    details['final_score'] = score
    details['max_score'] = max_score
    details['mandatory_criteria_met'] = mandatory_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }